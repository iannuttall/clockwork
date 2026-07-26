import AppKit
import SchedulerCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate, StatusItemMenuActionDelegate {
    private let settings: SettingsStore
    private let model: SchedulerModel
    private let updater: any UpdaterProviding
    private let openSettings: () -> Void
    private let statusItem: NSStatusItem
    private let menu = StatusItemMenu()
    private var notificationService: TaskNotificationService?
    private var refreshTimer: Timer?
    private var flaggedAttentionRuns: Set<String> = []
    private var flashTask: Task<Void, Never>?

    init(
        settings: SettingsStore,
        model: SchedulerModel,
        updater: any UpdaterProviding,
        openSettings: @escaping () -> Void)
    {
        self.settings = settings
        self.model = model
        self.updater = updater
        self.openSettings = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        self.configureStatusItem()
        self.notificationService = TaskNotificationService { [weak self] taskID in
            self?.openTask(taskID)
        }
        self.menu.delegate = self
        self.menu.actionDelegate = self
        self.statusItem.menu = self.menu
        self.rebuildMenu()
        self.startMonitoring()
    }

    private func configureStatusItem() {
        self.statusItem.autosaveName = "SchedulerStatusItem"
        if let button = self.statusItem.button {
            button.imagePosition = .imageOnly
            self.updateStatusItem()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        self.model.refresh()
        self.updateStatusItem()
        self.rebuildMenu()
    }

    private func updateStatusItem() {
        guard let button = self.statusItem.button else { return }

        self.flashTask?.cancel()
        self.flashTask = nil

        let attention = self.attentionSnapshots
        self.renderStatusItem(alerting: !attention.isEmpty)
        button.toolTip = Self.tooltip(attention)

        let current = Set(attention.compactMap { snapshot in
            snapshot.lastRun.map { "\(snapshot.id.uuidString.lowercased())-\($0.id)" }
        })
        let appeared = !current.subtracting(self.flaggedAttentionRuns).isEmpty
        self.flaggedAttentionRuns = current

        guard appeared else { return }
        self.startFlash()
    }

    private var attentionSnapshots: [TaskSnapshot] {
        self.model.snapshots.filter(self.model.needsAttention)
    }

    private func renderStatusItem(alerting: Bool) {
        guard let button = self.statusItem.button else { return }
        button.image = Self.statusItemImage(alerting: alerting)

        // An explicit tint opts the status item out of automatic menu-bar
        // adaptation. The alert dot is drawn into the image instead.
        button.contentTintColor = nil
    }

    private static func statusItemImage(alerting: Bool) -> NSImage? {
        guard let symbol = self.statusSymbol() else { return nil }
        guard alerting else {
            // A symbol-configured copy clears the template flag, so set it last.
            symbol.isTemplate = true
            return symbol
        }
        return self.badged(symbol)
    }

    private static func statusSymbol() -> NSImage? {
        guard let base = NSImage(
            systemSymbolName: Brand.statusSymbol,
            accessibilityDescription: Brand.displayName)
        else { return nil }
        return base.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)) ?? base
    }

    /// The badged image cannot be a template because macOS would tint the whole
    /// image, including the dot. Drawing inside the button's appearance keeps the
    /// timer white on a dark menu bar and black on a light one.
    private static func badged(_ symbol: NSImage) -> NSImage {
        let diameter: CGFloat = 9
        let moat: CGFloat = 1
        let overhang: CGFloat = 3
        let size = NSSize(width: symbol.size.width + overhang + moat, height: symbol.size.height)
        let badge = NSRect(x: size.width - diameter - moat, y: 0, width: diameter, height: diameter)

        let image = NSImage(size: size, flipped: false) { _ in
            let symbolRect = NSRect(origin: .zero, size: symbol.size)
            symbol.draw(in: symbolRect)

            NSColor.labelColor.set()
            symbolRect.fill(using: .sourceAtop)

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill()
            NSBezierPath(ovalIn: badge.insetBy(dx: -moat, dy: -moat)).fill()
            NSGraphicsContext.restoreGraphicsState()

            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: badge).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func startFlash() {
        self.flashTask = Task { @MainActor [weak self] in
            for beat in 0..<2 {
                self?.renderStatusItem(alerting: false)
                try? await Task.sleep(for: .milliseconds(110))
                guard !Task.isCancelled else { break }

                self?.renderStatusItem(alerting: true)
                guard beat < 1 else { break }
                try? await Task.sleep(for: .milliseconds(190))
                guard !Task.isCancelled else { break }
            }

            guard !Task.isCancelled else { return }
            self?.renderStatusItem(alerting: true)
            self?.flashTask = nil
        }
    }

    private static func tooltip(_ attention: [TaskSnapshot]) -> String {
        guard !attention.isEmpty else { return Brand.displayName }
        let messages = attention.prefix(4).compactMap { snapshot in
            snapshot.lastRun?.event.map { "\(snapshot.task.name): \($0.message)" }
        }
        let hidden = attention.count - messages.count
        let lines = hidden > 0 ? messages + ["…and \(hidden) more"] : messages
        return ([Brand.displayName, "\(attention.count) task\(attention.count == 1 ? "" : "s") need attention"] + lines)
            .joined(separator: "\n")
    }

    private func rebuildMenu() {
        self.menu.removeAllItems()
        let contentItem = NSMenuItem()
        let hosting = NSHostingView(rootView: MenuContentView(
            model: self.model,
            onAdd: { [weak self] in self?.addTask() },
            onOpen: { [weak self] in self?.presentSettings() },
            onOpenTask: { [weak self] in self?.openTask($0) }))
        let fitting = hosting.fittingSize
        hosting.frame = NSRect(x: 0, y: 0, width: max(fitting.width, 340), height: fitting.height)
        contentItem.view = hosting
        self.menu.addItem(contentItem)
        self.menu.addItem(.separator())

        for (sectionIndex, section) in MenuDescriptor.standard.sections.enumerated() {
            for entry in section.entries {
                switch entry {
                case let .action(title, action): self.menu.addItem(self.makeActionItem(title: title, action: action))
                }
            }
            if sectionIndex < MenuDescriptor.standard.sections.count - 1 { self.menu.addItem(.separator()) }
        }
    }

    private func startMonitoring() {
        self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.refresh()
                self.updateStatusItem()
                self.notificationService?.process(self.model.snapshots)
            }
        }
        if let refreshTimer = self.refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    private func makeActionItem(title: String, action: MenuDescriptor.MenuAction) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(self.handleMenuAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = Box(action)
        item.image = NSImage(systemSymbolName: action.systemImage, accessibilityDescription: title)
        if let equivalent = action.keyEquivalent {
            item.keyEquivalent = equivalent.key
            item.keyEquivalentModifierMask = equivalent.command ? .command : []
        }
        return item
    }

    @objc private func handleMenuAction(_ sender: NSMenuItem) {
        guard let action = (sender.representedObject as? Box)?.value else { return }
        self.perform(action)
    }

    nonisolated func statusItemMenu(_ menu: StatusItemMenu, didTrigger action: MenuDescriptor.MenuAction) {
        MainActor.assumeIsolated { self.perform(action) }
    }

    private func perform(_ action: MenuDescriptor.MenuAction) {
        switch action {
        case .add: self.addTask()
        case .open: self.presentSettings()
        case .checkForUpdates: self.updater.checkForUpdates()
        case .quit: NSApp.terminate(nil)
        }
    }

    private func addTask() {
        self.model.beginAdding()
        self.presentSettings()
    }

    private func openTask(_ id: UUID) {
        self.model.beginEditing(id)
        self.updateStatusItem()
        self.presentSettings()
    }

    private func presentSettings() {
        self.menu.cancelTracking()
        DispatchQueue.main.async { [openSettings] in
            openSettings()
        }
    }

    private final class Box {
        let value: MenuDescriptor.MenuAction
        init(_ value: MenuDescriptor.MenuAction) {
            self.value = value
        }
    }
}
