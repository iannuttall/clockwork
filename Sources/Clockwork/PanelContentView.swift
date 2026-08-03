import AppKit
import ClockworkCore
import SwiftUI

struct PanelContentView: View {
    @Bindable var model: ClockworkModel
    let updater: any UpdaterProviding
    let addTask: () -> Void
    let openSettings: () -> Void
    let openTask: (UUID) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            self.header
            Divider().opacity(0.5)
            self.content
            Divider().opacity(0.5)
            self.footer
        }
        .frame(width: PanelTheme.Panel.width)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: PanelTheme.Panel.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: PanelTheme.Panel.cornerRadius)
                .strokeBorder(PanelTheme.Colour.separator, lineWidth: 0.5)
        }
    }

    private var header: some View {
        HStack(spacing: PanelTheme.Space.regular) {
            Image(systemName: Brand.statusSymbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: PanelTheme.Space.hairline) {
                Text("Clockwork")
                    .font(PanelTheme.Typography.title)
                Text(self.headerSubtitle)
                    .font(PanelTheme.Typography.meta)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            if self.model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20, height: 20)
            }

            PanelIconButton(symbol: "plus", help: "Add scheduled task", action: self.addTask)
        }
        .padding(.horizontal, PanelTheme.Space.gutter)
        .padding(.vertical, PanelTheme.Space.comfy)
    }

    @ViewBuilder
    private var content: some View {
        if self.model.snapshots.isEmpty {
            self.emptyState
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(self.model.snapshots.enumerated()), id: \.element.id) { index, snapshot in
                        TaskPanelRow(
                            snapshot: snapshot,
                            attentionAcknowledged: self.model.isAttentionAcknowledged(
                                taskID: snapshot.id,
                                run: snapshot.lastRun),
                            disabled: self.model.isPerformingAction,
                            open: { self.openTask(snapshot.id) },
                            run: { self.model.runNow(snapshot.id) },
                            setEnabled: { self.model.setEnabled($0, for: snapshot.id) })

                        if index < self.model.snapshots.count - 1 {
                            Divider().padding(.leading, PanelTheme.Space.gutter + PanelTheme.Size.statusColumn)
                        }
                    }
                }
                .padding(.vertical, PanelTheme.Space.snug)
            }
            .frame(maxHeight: .infinity)
            .scrollIndicators(.automatic)
        }
    }

    private var emptyState: some View {
        VStack(spacing: PanelTheme.Space.regular) {
            Image(systemName: self.model.isRefreshing ? "circle.dotted" : "calendar.badge.plus")
                .font(.system(size: 24))
                .foregroundStyle(.quaternary)
            Text(self.model.isRefreshing ? "Loading tasks…" : "No scheduled tasks")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if !self.model.isRefreshing {
                Button("Add your first task", action: self.addTask)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(PanelTheme.Space.loose)
    }

    private var footer: some View {
        HStack(spacing: PanelTheme.Space.regular) {
            Text(self.footerText)
                .font(PanelTheme.Typography.meta)
                .foregroundStyle(self.model.errorMessage == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.red))
                .lineLimit(1)

            Spacer(minLength: 0)

            Button("Settings", action: self.openSettings)
                .buttonStyle(.plain)
                .font(PanelTheme.Typography.button)
                .foregroundStyle(.secondary)
                .keyboardShortcut(",")

            Menu {
                Button("Refresh") { self.model.refresh() }
                    .keyboardShortcut("r")
                Button("Add Scheduled Task…", action: self.addTask)
                    .keyboardShortcut("n")

                if self.updater.isAvailable {
                    Divider()
                    Button("Check for Updates…") {
                        self.dismiss()
                        self.updater.checkForUpdates()
                    }
                }

                Divider()
                Button("Quit Clockwork") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, PanelTheme.Space.gutter)
        .padding(.vertical, PanelTheme.Space.regular)
    }

    private var headerSubtitle: String {
        guard !self.model.snapshots.isEmpty else { return "Human-friendly recurring commands" }
        return "\(self.model.enabledCount) enabled · \(self.model.snapshots.count) total"
    }

    private var footerText: String {
        if let error = self.model.errorMessage { return error }
        if let notice = self.model.notice { return notice }
        let attention = self.model.snapshots.count(where: self.model.needsAttention)
        if attention > 0 { return "\(attention) task\(attention == 1 ? "" : "s") need attention" }
        return self.model.snapshots.isEmpty ? "Nothing scheduled" : "All tasks accounted for"
    }
}

private struct TaskPanelRow: View {
    let snapshot: TaskSnapshot
    let attentionAcknowledged: Bool
    let disabled: Bool
    let open: () -> Void
    let run: () -> Void
    let setEnabled: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: PanelTheme.Space.regular) {
            Circle()
                .fill(self.statusColor)
                .frame(width: PanelTheme.Size.statusDot, height: PanelTheme.Size.statusDot)
                .frame(width: PanelTheme.Size.statusColumn)

            Button(action: self.open) {
                VStack(alignment: .leading, spacing: PanelTheme.Space.tight) {
                    Text(self.snapshot.task.name)
                        .font(PanelTheme.Typography.rowTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(self.detailText)
                        .font(PanelTheme.Typography.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: PanelTheme.Space.tight) {
                PanelIconButton(symbol: "play.fill", help: "Run now", action: self.run)
                PanelIconButton(
                    symbol: self.snapshot.task.isEnabled ? "pause.fill" : "play.circle.fill",
                    help: self.snapshot.task.isEnabled ? "Pause schedule" : "Resume schedule",
                    action: { self.setEnabled(!self.snapshot.task.isEnabled) })
            }
            .frame(width: PanelTheme.Size.actionColumn)
            .opacity(self.hovering ? 1 : 0.55)
            .disabled(self.disabled)
        }
        .padding(.horizontal, PanelTheme.Space.gutter)
        .frame(height: PanelTheme.Size.rowHeight)
        .background(self.hovering ? PanelTheme.Colour.rowHover : .clear)
        .contentShape(Rectangle())
        .onHover { self.hovering = $0 }
        .opacity(self.snapshot.task.isEnabled ? 1 : 0.58)
    }

    private var statusColor: Color {
        guard let result = self.snapshot.lastRun else {
            return self.snapshot.task.isEnabled ? .blue : .secondary
        }
        if result.isRunning { return .orange }
        if result.requiresAttention { return self.attentionAcknowledged ? .green : .orange }
        return result.succeeded ? .green : .red
    }

    private var detailText: String {
        let schedule = self.snapshot.task.schedule.summary
        guard let result = self.snapshot.lastRun else { return "\(schedule) · Never run" }
        let status = result.requiresAttention && self.attentionAcknowledged ? "Seen" : result.summary
        let relative = result.startedAt.formatted(.relative(presentation: .named))
        return "\(schedule) · \(status) \(relative)"
    }
}

private struct PanelIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(self.help)
    }
}
