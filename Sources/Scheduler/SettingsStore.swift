import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults

    var launchAtLogin: Bool {
        didSet {
            self.defaults.set(self.launchAtLogin, forKey: Keys.launchAtLogin)
            guard self.launchAtLogin != oldValue else { return }
            do {
                if self.launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                self.launchAtLoginError = nil
            } catch {
                self.launchAtLoginError = error.localizedDescription
            }
        }
    }

    var launchAtLoginError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedValue = defaults.object(forKey: Keys.launchAtLogin) as? Bool
        self.launchAtLogin = storedValue ?? true
        if storedValue == nil {
            defaults.set(true, forKey: Keys.launchAtLogin)
        }
    }

    func registerAtLoginIfNeeded() {
        guard self.launchAtLogin else { return }
        do {
            switch SMAppService.mainApp.status {
            case .notRegistered, .notFound:
                try SMAppService.mainApp.register()
            case .requiresApproval, .enabled:
                break
            @unknown default: break
            }
            self.record(SMAppService.mainApp.status)
        } catch {
            self.launchAtLoginError = error.localizedDescription
            self.defaults.set("error: \(error.localizedDescription)", forKey: Keys.launchAtLoginStatus)
        }
    }

    private func record(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered:
            self.launchAtLoginError = "Scheduler is not registered as a login item."
            self.defaults.set("not registered", forKey: Keys.launchAtLoginStatus)
        case .requiresApproval:
            self.launchAtLoginError = "Allow Scheduler in System Settings → General → Login Items."
            self.defaults.set("requires approval", forKey: Keys.launchAtLoginStatus)
        case .enabled:
            self.launchAtLoginError = nil
            self.defaults.set("enabled", forKey: Keys.launchAtLoginStatus)
        case .notFound:
            self.launchAtLoginError = "Install Scheduler in Applications, then reopen it."
            self.defaults.set("not found", forKey: Keys.launchAtLoginStatus)
        @unknown default:
            self.launchAtLoginError = "macOS could not confirm the login item status."
            self.defaults.set("unknown", forKey: Keys.launchAtLoginStatus)
        }
    }

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let launchAtLoginStatus = "launchAtLoginStatus"
    }
}
