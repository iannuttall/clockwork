import AppKit
import SchedulerCore
import SwiftUI

@main
struct SchedulerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: SettingsStore
    @State private var model: SchedulerModel

    init() {
        let settings = SettingsStore()
        let model = SchedulerModel()
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
