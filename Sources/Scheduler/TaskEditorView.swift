import AppKit
import SchedulerCore
import SwiftUI

struct TasksPreferencesPane: View {
    @Bindable var model: SchedulerModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Tasks").font(.headline)
                    Spacer()
                    Button { self.model.beginAdding() } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Add scheduled task")
                }
                .padding(14)
                Divider()
                if self.model.snapshots.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("No tasks yet").font(.headline)
                        Button("Add Task") { self.model.beginAdding() }
                        Spacer()
                    }
                } else {
                    List(selection: self.$model.selectedTaskID) {
                        ForEach(self.model.snapshots) { snapshot in
                            TaskListRow(
                                snapshot: snapshot,
                                attentionAcknowledged: self.model.isAttentionAcknowledged(
                                    taskID: snapshot.id,
                                    run: snapshot.lastRun))
                                .tag(snapshot.id)
                        }
                    }
                    .listStyle(.sidebar)
                    .onChange(of: self.model.selectedTaskID) { _, id in
                        if let id { self.model.beginEditing(id) }
                    }
                }
            }
            .frame(width: 250)
            Divider()
            Group {
                if self.model.draft != nil {
                    TaskEditorForm(model: self.model, draft: Binding(
                        get: { self.model.draft ?? TaskDraft() },
                        set: { self.model.draft = $0 }))
                } else {
                    ContentUnavailableView(
                        "Select a task",
                        systemImage: "clock",
                        description: Text("Choose a task on the left, or add a new one."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct TaskListRow: View {
    let snapshot: TaskSnapshot
    let attentionAcknowledged: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(self.snapshot.task.isEnabled ? self.statusColor : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(self.snapshot.task.name).lineLimit(1)
            }
            Text(self.snapshot.task.schedule.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
        .opacity(self.snapshot.task.isEnabled ? 1 : 0.6)
    }

    private var statusColor: Color {
        guard let result = self.snapshot.lastRun else { return .blue }
        if result.isRunning { return .orange }
        if result.requiresAttention { return self.attentionAcknowledged ? .green : .orange }
        return result.succeeded ? .green : .red
    }
}

private struct TaskEditorForm: View {
    @Bindable var model: SchedulerModel
    @Binding var draft: TaskDraft
    @State private var showingDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    PaneTitle(
                        title: self.draft.id == nil ? "New Task" : "Edit Task",
                        subtitle: self.draft.schedule.summary)
                    Spacer()
                    Toggle("Enabled", isOn: self.$draft.isEnabled)
                        .toggleStyle(.switch)
                }

                SettingsSection(title: "Task") {
                    TextField("Name", text: self.$draft.name, prompt: Text("Update Codex"))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Commands").font(.callout.weight(.medium))
                        TextEditor(text: self.$draft.commandsText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 90)
                            .padding(6)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                        Text("One command per line. They run in order and stop on the first failure.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("Working folder (optional)", text: self.$draft.workingDirectory)
                        Button("Choose…") { self.chooseDirectory() }
                    }
                }

                SettingsSection(title: "When") {
                    Picker("Schedule", selection: self.$draft.scheduleKind) {
                        ForEach(ScheduleKind.allCases) { kind in Text(kind.label).tag(kind) }
                    }
                    .pickerStyle(.segmented)

                    switch self.draft.scheduleKind {
                    case .interval:
                        HStack {
                            Text("Run every")
                            Stepper(value: self.$draft.intervalValue, in: 1...1440) {
                                Text("\(self.draft.intervalValue)")
                                    .monospacedDigit()
                                    .frame(minWidth: 32)
                            }
                            Picker("", selection: self.$draft.intervalUnit) {
                                Text("minutes").tag(IntervalUnit.minutes)
                                Text("hours").tag(IntervalUnit.hours)
                            }
                            .labelsHidden()
                            .frame(width: 110)
                            Spacer()
                        }
                    case .daily:
                        TimeSelector(hour: self.$draft.hour, minute: self.$draft.minute, prefix: "Run every day at")
                    case .weekly:
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                ForEach(Weekday.allCases) { day in
                                    DayButton(day: day, selected: self.draft.weekdays.contains(day)) {
                                        if self.draft.weekdays.contains(day) {
                                            self.draft.weekdays.remove(day)
                                        } else {
                                            self.draft.weekdays.insert(day)
                                        }
                                    }
                                }
                            }
                            TimeSelector(hour: self.$draft.hour, minute: self.$draft.minute, prefix: "Run at")
                        }
                    }
                    Text(self.draft.schedule.summary)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.tint)
                }

                if let id = self.draft.id,
                   self.model.snapshots.contains(where: { $0.id == id })
                {
                    RunHistoryCard(
                        runs: self.model.runs(for: id),
                        run: { self.model.runNow(id) },
                        isAcknowledged: {
                            self.model.isAttentionAcknowledged(taskID: id, run: $0)
                        },
                        acknowledge: {
                            self.model.acknowledgeAttention(for: id)
                        })
                }

                if let error = self.model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                } else if let notice = self.model.notice {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }

                HStack {
                    if let id = self.draft.id {
                        Button("Delete", role: .destructive) { self.showingDeleteConfirmation = true }
                            .confirmationDialog("Delete this task?", isPresented: self.$showingDeleteConfirmation) {
                                Button("Delete Task", role: .destructive) { self.model.delete(id) }
                            } message: {
                                Text("Its schedule will be removed from launchd. Existing logs stay on this Mac.")
                            }
                    }
                    Spacer()
                    Button("Cancel") { self.model.cancelEditing() }
                    Button("Save Task") { self.model.saveDraft() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(self.draft.validationError != nil)
                }
            }
            .padding(28)
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            self.draft.workingDirectory = url.path
        }
    }
}

private struct TimeSelector: View {
    @Binding var hour: Int
    @Binding var minute: Int
    let prefix: String

    var body: some View {
        HStack {
            Text(self.prefix)
            Picker("Hour", selection: self.$hour) {
                ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 72)
            Text(":")
            Picker("Minute", selection: self.$minute) {
                ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) {
                    Text(String(format: "%02d", $0)).tag($0)
                }
            }
            .labelsHidden()
            .frame(width: 72)
            Spacer()
        }
    }
}

private struct DayButton: View {
    let day: Weekday
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(self.day.shortName, action: self.action)
            .buttonStyle(.bordered)
            .tint(self.selected ? .accentColor : .secondary)
    }
}

private struct RunHistoryCard: View {
    let runs: [TaskRunResult]
    let run: () -> Void
    let isAcknowledged: (TaskRunResult) -> Bool
    let acknowledge: () -> Void
    @State private var selectedRunID: String?

    var body: some View {
        SettingsSection(title: "Run History") {
            HStack {
                Text(self.runs.isEmpty ? "No runs yet" : "Latest \(min(self.runs.count, 50)) runs")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Run Now", action: self.run)
            }

            if !self.runs.isEmpty {
                VStack(spacing: 0) {
                    ForEach(self.runs.prefix(10)) { result in
                        Button {
                            self.selectedRunID = result.id
                            if result.requiresAttention {
                                self.acknowledge()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: self.symbol(for: result))
                                    .foregroundStyle(self.color(for: result))
                                    .frame(width: 16)
                                Text(self.label(for: result))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let duration = self.duration(for: result) {
                                    Text(duration)
                                }
                                Text(result.startedAt.formatted(date: .abbreviated, time: .shortened))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(self.selectedResult.id == result.id ? Color.accentColor.opacity(0.12) : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if result.id != self.runs.prefix(10).last?.id { Divider() }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))

                if let event = self.selectedResult.event {
                    AttentionRunCard(
                        event: event,
                        acknowledged: self.isAcknowledged(self.selectedResult),
                        acknowledge: self.acknowledge)
                }

                ScrollView {
                    Text(self.selectedResult.combinedOutput.isEmpty ? "No output" : self.selectedResult.combinedOutput)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(self.selectedResult.combinedOutput.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 80, maxHeight: 180)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var selectedResult: TaskRunResult {
        self.runs.first(where: { $0.id == self.selectedRunID }) ?? self.runs[0]
    }

    private func symbol(for result: TaskRunResult) -> String {
        if result.isRunning { return "arrow.trianglehead.2.clockwise.rotate.90" }
        if result.requiresAttention {
            return self.isAcknowledged(result) ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        }
        return result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private func color(for result: TaskRunResult) -> Color {
        if result.isRunning { return .orange }
        if result.requiresAttention { return self.isAcknowledged(result) ? .green : .orange }
        return result.succeeded ? .green : .red
    }

    private func label(for result: TaskRunResult) -> String {
        guard result.requiresAttention else { return result.summary }
        if self.isAcknowledged(result) { return "Seen" }
        return result.event.map { "\($0.title): needs attention" } ?? result.summary
    }

    private func duration(for result: TaskRunResult) -> String? {
        guard let finishedAt = result.finishedAt else { return nil }
        let seconds = max(0, Int(finishedAt.timeIntervalSince(result.startedAt)))
        return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s"
    }
}

private struct AttentionRunCard: View {
    let event: TaskRunEvent
    let acknowledged: Bool
    let acknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    self.acknowledged ? "\(self.event.title) seen" : self.event.title,
                    systemImage: self.acknowledged ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(self.accentColor)
                Spacer()
                if !self.acknowledged {
                    Button("Mark as seen", action: self.acknowledge)
                        .controlSize(.small)
                }
            }

            Text(self.event.message)
                .font(.callout)
                .textSelection(.enabled)

            if let nextStep = self.event.nextStep {
                Text("Next step")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(nextStep)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(nextStep, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy next step")
                }
            }
        }
        .padding(10)
        .background(self.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(self.accentColor.opacity(0.35)))
    }

    private var accentColor: Color {
        self.acknowledged ? .green : .orange
    }
}
