import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    struct Dependencies {
        let settings: SettingsStore
        let model: ClockworkModel
    }

    let updater: any UpdaterProviding = makeUpdaterController()

    private var settings: SettingsStore?
    private var model: ClockworkModel?
    private var panelController: PanelController?
    private var settingsWindowController: SettingsWindowController?

    func configure(_ dependencies: Dependencies) {
        self.settings = dependencies.settings
        self.model = dependencies.model
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Self.isOnlyRunningInstance() else {
            NSApp.terminate(nil)
            return
        }
        guard let settings = self.settings, let model = self.model else { return }
        let closedLegacyApp = Self.terminateLegacyScheduler()
        NSApp.setActivationPolicy(.accessory)
        settings.registerAtLoginIfNeeded()
        let panelController = PanelController(
            model: model,
            updater: self.updater,
            openSettings: { self.openSettings() })
        self.panelController = panelController

        if closedLegacyApp {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                model.refresh()
            }
        } else {
            model.refresh()
        }

        switch ProcessInfo.processInfo.environment["CLOCKWORK_OPEN_ON_LAUNCH"] {
        case "1":
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                panelController.open()
            }
        case "settings":
            self.openSettings()
        default:
            break
        }
    }

    func openSettings() {
        guard let settings = self.settings, let model = self.model else { return }
        if self.settingsWindowController == nil {
            self.settingsWindowController = SettingsWindowController(
                settings: settings,
                model: model,
                updater: self.updater)
        }
        self.settingsWindowController?.present()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        self.openSettings()
        return true
    }

    private static func isOnlyRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let peers = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        return peers.isEmpty
    }

    /// The private pre-release app can otherwise recreate its old jobs while the
    /// one-time data migration is moving them into Clockwork.
    private static func terminateLegacyScheduler() -> Bool {
        let legacy = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.iannuttall.scheduler"
        }
        legacy.forEach { $0.terminate() }
        return !legacy.isEmpty
    }
}
