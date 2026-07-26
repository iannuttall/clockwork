import Foundation

/// Abstraction over the auto-updater so the rest of the app never imports Sparkle
/// directly, and so unsigned/dev builds can run with a no-op implementation.
@MainActor
protocol UpdaterProviding: AnyObject {
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }
    func checkForUpdates()
}

/// Used for unsigned/dev builds and when Sparkle is compiled out.
@MainActor
final class DisabledUpdaterController: UpdaterProviding {
    let isAvailable = false
    let unavailableReason: String?

    init(unavailableReason: String? = "Updates are unavailable in this build.") {
        self.unavailableReason = unavailableReason
    }

    func checkForUpdates() {}
}

#if canImport(Sparkle) && ENABLE_SPARKLE
import Sparkle

@MainActor
final class SparkleUpdaterController: UpdaterProviding {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil)

    let isAvailable = true
    let unavailableReason: String? = nil

    func checkForUpdates() {
        self.controller.checkForUpdates(nil)
    }
}
#endif

/// Picks a real updater only for a signed, bundled build; otherwise no-op so dev
/// runs never show Sparkle dialogs or errors.
@MainActor
func makeUpdaterController() -> any UpdaterProviding {
    let bundleURL = Bundle.main.bundleURL
    guard bundleURL.pathExtension == "app" else {
        return DisabledUpdaterController()
    }
    let feedURL = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let publicKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard feedURL.isEmpty == false, publicKey.isEmpty == false else {
        return DisabledUpdaterController(unavailableReason: "Updates are unavailable in this build.")
    }
    #if canImport(Sparkle) && ENABLE_SPARKLE
    return SparkleUpdaterController()
    #else
    return DisabledUpdaterController()
    #endif
}
