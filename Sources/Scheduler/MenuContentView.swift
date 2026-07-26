import SchedulerCore
import SwiftUI

struct MenuContentView: View {
    @Bindable var model: SchedulerModel
    let onAdd: () -> Void
    let onOpen: () -> Void
    let onOpenTask: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scheduler")
                        .font(.headline)
                    Text(self.headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: self.onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Add scheduled task")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if self.model.snapshots.isEmpty {
                EmptyMenuView(onAdd: self.onAdd)
            } else {
                VStack(spacing: 0) {
                    ForEach(self.model.snapshots.prefix(8)) { snapshot in
                        TaskMenuRow(
                            snapshot: snapshot,
                            attentionAcknowledged: self.model.isAttentionAcknowledged(
                                taskID: snapshot.id,
                                run: snapshot.lastRun),
                            setEnabled: { self.model.setEnabled($0, for: snapshot.id) },
                            run: { self.model.runNow(snapshot.id) },
                            logs: { self.onOpenTask(snapshot.id) })
                        if snapshot.id != self.model.snapshots.prefix(8).last?.id { Divider() }
                    }
                }
            }

            if self.model.snapshots.count > 8 {
                Button("Show all \(self.model.snapshots.count) tasks…", action: self.onOpen)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .frame(width: 340)
    }

    private var headerSubtitle: String {
        if self.model.snapshots.isEmpty { return "Nothing scheduled yet" }
        let enabled = self.model.enabledCount
        return "\(enabled) enabled · \(self.model.snapshots.count) total"
    }
}

private struct EmptyMenuView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 27))
                .foregroundStyle(.secondary)
            Text("No scheduled tasks")
                .font(.headline)
            Text("Run commands automatically without writing crontab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add your first task", action: self.onAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 24)
    }
}

private struct TaskMenuRow: View {
    let snapshot: TaskSnapshot
    let attentionAcknowledged: Bool
    let setEnabled: (Bool) -> Void
    let run: () -> Void
    let logs: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: self.logs) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(self.statusColor)
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.snapshot.task.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(self.snapshot.task.schedule.summary)
                            Text("·")
                            Text(self.lastRunText)
                                .foregroundStyle(self.snapshot.lastRun?.succeeded == false ? Color.red : Color
                                    .secondary)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("View task and run logs")

            MenuIconButton(symbol: "play.fill", help: "Run now", action: self.run)
            MenuIconButton(symbol: "doc.text", help: "View run logs", action: self.logs)
            MenuIconButton(
                symbol: self.snapshot.task.isEnabled ? "pause.fill" : "play.circle.fill",
                help: self.snapshot.task.isEnabled ? "Pause schedule" : "Resume schedule",
                action: { self.setEnabled(!self.snapshot.task.isEnabled) })
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .opacity(self.snapshot.task.isEnabled ? 1 : 0.55)
    }

    private var statusColor: Color {
        guard let result = self.snapshot.lastRun else { return self.snapshot.task.isEnabled ? .blue : .secondary }
        if result.isRunning { return .orange }
        if result.requiresAttention { return self.attentionAcknowledged ? .green : .orange }
        return result.succeeded ? .green : .red
    }

    private var lastRunText: String {
        guard let result = self.snapshot.lastRun else { return "Never run" }
        if result.isRunning { return "Running now…" }
        if result.requiresAttention, self.attentionAcknowledged {
            return "Seen · \(result.startedAt.formatted(.relative(presentation: .named)))"
        }
        return "\(result.summary) · \(result.startedAt.formatted(.relative(presentation: .named)))"
    }
}

private struct MenuIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(self.help)
    }
}
