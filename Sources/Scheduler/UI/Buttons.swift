import SwiftUI

// MARK: - Buttons

//
// Prefer native button styles — they're free, accessible, and match the system:
//
//   Button("Save") { … }.buttonStyle(.borderedProminent)        // primary
//   Button("Cancel") { … }.buttonStyle(.bordered)               // secondary
//   Button("Delete", role: .destructive) { … }                  // destructive
//   Button { … } label: { Image(systemName: "gear") }.buttonStyle(.borderless) // icon
//   Button("Learn more") { … }.buttonStyle(.link)               // link-style
//
// Add `.controlSize(.small)` for the compact look used in menus and prefs panes.
// The thin wrappers below exist only to name the primary/secondary intent at call
// sites; reach for the native styles directly whenever that reads clearer.

/// Bordered-prominent button carrying the primary action (accent-tinted).
struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(self.title, action: self.action)
            .buttonStyle(.borderedProminent)
            .tint(Brand.accent)
    }
}

/// Bordered button for a secondary action.
struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(self.title, action: self.action)
            .buttonStyle(.bordered)
    }
}

/// A pressed/scale icon-button style for compact controls inside cards and menus.
/// Apply to a `Button` whose label is a small `Image(systemName:)`.
struct CardIconButtonStyle: ButtonStyle {
    var isHighlighted: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(Layout.spacing1)
            .background {
                RoundedRectangle(cornerRadius: Layout.spacing1, style: .continuous)
                    .fill(MenuHighlightStyle.secondary(self.isHighlighted).opacity(configuration.isPressed ? 0.18 : 0))
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
