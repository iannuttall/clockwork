import AppKit
import ClockworkCore
import SwiftUI

@main
struct ClockworkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: SettingsStore
    @State private var model: ClockworkModel

    init() {
        let settings = SettingsStore()
        let model = ClockworkModel()
        _settings = State(wrappedValue: settings)
        _model = State(wrappedValue: model)
        self.appDelegate.configure(.init(settings: settings, model: model))
    }

    var body: some Scene {
        Settings {
            PreferencesView(settings: self.settings, model: self.model, updater: self.appDelegate.updater)
        }
        .windowResizability(.contentSize)
    }
}
