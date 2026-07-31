import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    struct Dependencies {
        let settings: SettingsStore
        let model: SchedulerModel
    }

    let updater: any UpdaterProviding = makeUpdaterController()

    private var settings: SettingsStore?
    private var model: SchedulerModel?
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
        NSApp.setActivationPolicy(.accessory)
        settings.registerAtLoginIfNeeded()
        let panelController = PanelController(
            model: model,
            updater: self.updater,
            openSettings: { self.openSettings() })
        self.panelController = panelController

        switch ProcessInfo.processInfo.environment["SCHEDULER_OPEN_ON_LAUNCH"] {
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
}
