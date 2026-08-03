import AppKit
import ClockworkCore
import Observation
import SwiftUI

/// A menu-like panel that can accept keyboard input without becoming a normal app window.
final class ClockworkPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

/// Owns the status item and a persistent SwiftUI panel.
///
/// The panel is created once and shown from the model's current snapshot. Opening it never
/// performs I/O, rebuilds a hosting tree, or asks SwiftUI for an intrinsic size.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let model: ClockworkModel
    private let updater: any UpdaterProviding
    private let openSettings: () -> Void
    private let statusItem: NSStatusItem

    private var panel: ClockworkPanel?
    private var hostingView: NSHostingView<PanelContentView>?
    private var outsideClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var refreshTimer: Timer?
    private var notificationService: TaskNotificationService?
    private var flaggedAttentionRuns: Set<String> = []
    private var flashTask: Task<Void, Never>?

    var isOpen: Bool {
        self.panel?.isVisible == true
    }

    init(
        model: ClockworkModel,
        updater: any UpdaterProviding,
        openSettings: @escaping () -> Void)
    {
        self.model = model
        self.updater = updater
        self.openSettings = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        self.configureStatusItem()
        self.notificationService = TaskNotificationService { [weak self] taskID in
            self?.openTask(taskID)
        }
        self.observeStatus()
        self.scheduleRefreshTimer()
    }

    // MARK: - Status item

    private func configureStatusItem() {
        guard let button = self.statusItem.button else { return }
        self.statusItem.autosaveName = "ClockworkStatusItem"
        button.target = self
        button.action = #selector(self.statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        self.updateStatusItem()
    }

    private func observeStatus() {
        withObservationTracking {
            _ = self.model.snapshots
            _ = self.model.attentionStateRevision
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateStatusItem()
                self.notificationService?.process(self.model.snapshots)
                self.observeStatus()
            }
        }
    }

    private func updateStatusItem() {
        guard let button = self.statusItem.button else { return }
        self.flashTask?.cancel()
        self.flashTask = nil

        let attention = self.model.snapshots.filter(self.model.needsAttention)
        self.renderStatusItem(alerting: !attention.isEmpty)
        button.toolTip = Self.tooltip(attention)

        let current = Set(attention.compactMap { snapshot in
            snapshot.lastRun.map { "\(snapshot.id.uuidString.lowercased())-\($0.id)" }
        })
        let appeared = !current.subtracting(self.flaggedAttentionRuns).isEmpty
        self.flaggedAttentionRuns = current
        if appeared { self.startFlash() }
    }

    private func renderStatusItem(alerting: Bool) {
        guard let button = self.statusItem.button else { return }
        button.image = Self.statusItemImage(alerting: alerting)

        // Any explicit tint opts the button out of menu-bar light/dark adaptation.
        button.contentTintColor = nil
    }

    private static func statusItemImage(alerting: Bool) -> NSImage? {
        guard let symbol = self.statusSymbol() else { return nil }
        guard alerting else {
            // Symbol configuration returns a copy with its template flag cleared.
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

    /// The alert image cannot be a template or macOS would tint the badge too.
    /// Deferred drawing resolves `labelColor` inside the menu bar's own appearance.
    private static func badged(_ symbol: NSImage) -> NSImage {
        let diameter = PanelTheme.Size.menuBarBadge
        let moat = PanelTheme.Size.menuBarBadgeMoat
        let overhang = PanelTheme.Size.menuBarBadgeOverhang
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

    // MARK: - Panel

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            self.showContextMenu()
        } else {
            self.toggle()
        }
    }

    func toggle() {
        if self.isOpen {
            self.close()
        } else {
            self.open()
        }
    }

    func open() {
        let panel = self.panel ?? self.makePanel()
        self.panel = panel
        self.sizeOnOpen(panel)
        self.position(panel)

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        self.startEventMonitoring()
        self.scheduleRefreshTimer()

        // Paint first from the warm snapshot; fresh disk state lands asynchronously.
        self.model.refresh()
    }

    func close() {
        self.stopEventMonitoring()
        self.panel?.orderOut(nil)
        self.scheduleRefreshTimer()
    }

    private func makePanel() -> ClockworkPanel {
        let panel = ClockworkPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelTheme.Panel.width, height: PanelTheme.Panel.minHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let root = PanelContentView(
            model: self.model,
            updater: self.updater,
            addTask: { [weak self] in self?.addTask() },
            openSettings: { [weak self] in self?.presentSettings() },
            openTask: { [weak self] in self?.openTask($0) },
            dismiss: { [weak self] in self?.close() })
        let hosting = NSHostingView(rootView: root)

        // Intrinsic sizing makes SwiftUI measurement part of every show/update and
        // lets content changes move the panel away from the menu bar.
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.hostingView = hosting
        return panel
    }

    private func sizeOnOpen(_ panel: NSPanel) {
        let content = CGFloat(self.model.snapshots.count) * PanelTheme.Size.rowHeight
        let listInsets = PanelTheme.Space.snug * 2
        let estimated = PanelTheme.Panel.chromeHeight + content + listInsets
        let available = (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? PanelTheme.Panel.maxHeight
        let ceiling = min(PanelTheme.Panel.maxHeight, available - 40)
        let floor = self.model.snapshots.isEmpty ? PanelTheme.Panel.emptyHeight : PanelTheme.Panel.minHeight
        let height = min(max(estimated, floor), ceiling)
        panel.setContentSize(NSSize(width: PanelTheme.Panel.width, height: height))
    }

    private func position(_ panel: NSPanel) {
        guard let button = self.statusItem.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main
        else { return }

        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let size = panel.frame.size
        var origin = NSPoint(
            x: buttonRect.midX - size.width / 2,
            y: buttonRect.minY - size.height - PanelTheme.Panel.menuBarGap)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = max(origin.y, visible.minY + 8)
        panel.setFrameOrigin(origin)
    }

    // MARK: - Events and refresh

    private func startEventMonitoring() {
        self.stopEventMonitoring()
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        self.outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        self.localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func stopEventMonitoring() {
        if let outsideClickMonitor = self.outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let localKeyMonitor = self.localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
        switch event.keyCode {
        case 53:
            self.close()
            return true
        case 45 where command:
            self.addTask()
            return true
        case 43 where command:
            self.presentSettings()
            return true
        case 15 where command:
            self.model.refresh()
            return true
        case 12 where command:
            NSApp.terminate(nil)
            return true
        default:
            return false
        }
    }

    private func scheduleRefreshTimer() {
        self.refreshTimer?.invalidate()
        let interval = self.isOpen ? 2.0 : 15.0
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        }
        self.refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Menus opened from the panel take key focus; the outside-click monitor owns dismissal.
    }

    // MARK: - Actions

    private func addTask() {
        self.model.beginAdding()
        self.presentSettings()
    }

    private func openTask(_ id: UUID) {
        self.model.beginEditing(id)
        self.presentSettings()
    }

    private func presentSettings() {
        self.close()
        self.openSettings()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(self.refresh), keyEquivalent: "r")
        menu.addItem(withTitle: "Add Scheduled Task…", action: #selector(self.add), keyEquivalent: "n")
        menu.addItem(withTitle: "Settings…", action: #selector(self.settings), keyEquivalent: ",")
        menu.addItem(.separator())
        if self.updater.isAvailable {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(self.checkForUpdates), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Quit Clockwork", action: #selector(self.quit), keyEquivalent: "q")
        for item in menu.items {
            item.target = self
        }

        self.statusItem.menu = menu
        self.statusItem.button?.performClick(nil)
        self.statusItem.menu = nil
    }

    @objc private func refresh() {
        self.model.refresh()
    }

    @objc private func add() {
        self.addTask()
    }

    @objc private func settings() {
        self.presentSettings()
    }

    @objc private func checkForUpdates() {
        self.close()
        self.updater.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
