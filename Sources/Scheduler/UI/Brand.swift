import SwiftUI

/// The single reskin point for the app's look. **Edit this to reskin the app.**
///
/// Everything visual that should change per-app — the accent color, the menu-bar
/// symbol, the display name — funnels through here so the component kit and the
/// status item stay consistent without hunting through views.
enum Brand {
    /// Accent used by links, buttons, and card tints. Defaults to the system
    /// accent so the app honors the user's macOS accent preference; set a fixed
    /// `Color` here to lock in a brand color instead.
    static let accent: Color = .accentColor

    /// SF Symbol shown in the menu bar (used by `StatusItemController`). Pick any
    /// system symbol that reads well as a template image at ~16pt.
    static let statusSymbol: String = "timer"

    /// Human-facing app name. Mirrors `Scheduler`; surfaced in About/links.
    static let displayName: String = "Scheduler"
}
