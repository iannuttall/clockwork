import SwiftUI

private enum SidebarPane: String, CaseIterable, Identifiable {
    case tasks
    case general
    case commandLine
    case about

    var id: String {
        self.rawValue
    }

    var title: String {
        switch self {
        case .tasks: "Tasks"
        case .general: "General"
        case .commandLine: "Command Line"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .tasks: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .general: "gearshape"
        case .commandLine: "terminal"
        case .about: "info.circle"
        }
    }
}

struct PreferencesView: View {
    @Bindable var settings: SettingsStore
    @Bindable var model: ClockworkModel
    let updater: any UpdaterProviding
    @State private var pane = SidebarPane.tasks

    var body: some View {
        NavigationSplitView {
            List(SidebarPane.allCases, selection: self.$pane) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            Group {
                switch self.pane {
                case .tasks: TasksPreferencesPane(model: self.model)
                case .general: GeneralPreferencesPane(settings: self.settings)
                case .commandLine: CommandLinePane()
                case .about: AboutPreferencesPane(updater: self.updater)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 900, height: 620)
        .onAppear { self.model.refresh() }
    }
}

private struct GeneralPreferencesPane: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PaneTitle(title: "General", subtitle: "Keep Clockwork available without keeping it in your Dock.")
            Card {
                Toggle("Start Clockwork automatically at login", isOn: self.$settings.launchAtLogin)
                Text("Your scheduled jobs use launchd and continue to run even when this window is closed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let error = self.settings.launchAtLoginError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            Spacer()
        }
        .padding(28)
    }
}

private struct CommandLinePane: View {
    @State private var installMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PaneTitle(
                title: "Command Line",
                subtitle: "Let you or an AI agent manage the same tasks without clicking around.")
            Card {
                Text("Install the `clockwork` command")
                    .font(.headline)
                Text("Installs to ~/.local/bin/clockwork. It supports JSON output and full task management.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Install CLI") { self.installCLI() }
                        .buttonStyle(.borderedProminent)
                    if let installMessage {
                        Text(installMessage)
                            .font(.footnote)
                            .foregroundStyle(installMessage.hasPrefix("Installed") ? .green : .red)
                    }
                }
                Divider()
                Text("Examples")
                    .font(.headline)
                Text([
                    "clockwork list --json",
                    "clockwork add --name 'Update Codex' --command 'codex update' --every 6h",
                    "clockwork disable 'Update Codex'",
                    "clockwork run 'Update Codex'",
                ].joined(separator: "\n"))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(28)
    }

    private func installCLI() {
        do {
            guard let executable = Bundle.main.executableURL else { throw CLIInstallError.missingExecutable }
            let source = executable.deletingLastPathComponent().appendingPathComponent("clockworkcli")
            guard FileManager.default.fileExists(atPath: source.path) else { throw CLIInstallError.missingCLI }
            let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
            let destination = directory.appendingPathComponent("clockwork")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            self.installMessage = "Installed to ~/.local/bin/clockwork"
        } catch {
            self.installMessage = error.localizedDescription
        }
    }
}

private enum CLIInstallError: LocalizedError {
    case missingExecutable
    case missingCLI

    var errorDescription: String? {
        switch self {
        case .missingExecutable: "Could not locate the Clockwork app."
        case .missingCLI: "This build does not contain the Clockwork CLI."
        }
    }
}

private struct AboutPreferencesPane: View {
    let updater: any UpdaterProviding

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: Brand.statusSymbol)
                .font(.system(size: 50))
                .foregroundStyle(.tint)
            Text("Clockwork")
                .font(.title2.weight(.semibold))
            Text("Version \(self.version)")
                .foregroundStyle(.secondary)
            Text("Simple recurring commands, powered by launchd.")
                .foregroundStyle(.secondary)
            Button("Check for Updates…") { self.updater.checkForUpdates() }
                .disabled(!self.updater.isAvailable)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}

struct PaneTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(self.title).font(.title2.weight(.semibold))
            Text(self.subtitle).foregroundStyle(.secondary)
        }
    }
}
