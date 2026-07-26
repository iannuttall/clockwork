import AppKit

/// `NSMenu` subclass that routes global key equivalents while the menu is open.
/// even while the menu is open and the cursor is over the hosted SwiftUI card.
///
/// `performKeyEquivalent` is inherited as nonisolated, so the delegate is a plain
/// (nonisolated) protocol and the controller hops to the main actor internally.
final class StatusItemMenu: NSMenu {
    weak var actionDelegate: StatusItemMenuActionDelegate?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let action = Self.persistentAction(for: event) {
            self.actionDelegate?.statusItemMenu(self, didTrigger: action)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private nonisolated static func persistentAction(for event: NSEvent) -> MenuDescriptor.MenuAction? {
        guard event.type == .keyDown else { return nil }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers == .command else { return nil }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "n": return .add
        case ",": return .open
        case "q": return .quit
        default: return nil
        }
    }
}

protocol StatusItemMenuActionDelegate: AnyObject {
    func statusItemMenu(_ menu: StatusItemMenu, didTrigger action: MenuDescriptor.MenuAction)
}
