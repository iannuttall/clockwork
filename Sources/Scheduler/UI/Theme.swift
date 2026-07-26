import SwiftUI

extension EnvironmentValues {
    /// Set on views hosted inside an `NSMenuItem` while that row is highlighted, so
    /// components can swap to selection-appropriate colors (see `MenuHighlightStyle`).
    @Entry var menuItemHighlighted: Bool = false
}

/// Semantic colors for content hosted inside a native `NSMenu`. Mapping
/// `isHighlighted -> NSColor` keeps text legible when a row is selected and gives
/// free light/dark adaptation via the system's semantic colors.
enum MenuHighlightStyle {
    static let selectionText = Color(nsColor: .selectedMenuItemTextColor)
    static let normalPrimaryText = Color(nsColor: .controlTextColor)
    static let normalSecondaryText = Color(nsColor: .secondaryLabelColor)

    static func primary(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : self.normalPrimaryText
    }

    static func secondary(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText.opacity(0.86) : self.normalSecondaryText
    }

    static func error(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : Color(nsColor: .systemRed)
    }

    static func progressTrack(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText.opacity(0.22) : Color(nsColor: .tertiaryLabelColor).opacity(0.22)
    }

    static func progressTint(_ highlighted: Bool, fallback: Color) -> Color {
        highlighted ? self.selectionText : fallback
    }

    static func selectionBackground(_ highlighted: Bool) -> Color {
        highlighted ? Color(nsColor: .selectedContentBackgroundColor) : .clear
    }
}

/// Spacing and corner-radius constants shared across the kit. Keep components on
/// this scale so layouts line up: spacing 4/6/8/10/12, radii 6 (controls),
/// 8/10 (cards), and a 6pt meter/progress-bar height.
enum Layout {
    static let spacing1: CGFloat = 4
    static let spacing2: CGFloat = 6
    static let spacing3: CGFloat = 8
    static let spacing4: CGFloat = 10
    static let spacing5: CGFloat = 12

    static let controlRadius: CGFloat = 6
    static let cardRadius: CGFloat = 8
    static let cardRadiusLarge: CGFloat = 10

    static let barHeight: CGFloat = 6
}
