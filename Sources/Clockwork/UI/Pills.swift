import SwiftUI

// MARK: - Pills, Badges, Dots, Tags

//
// All share the same recipe: a tinted `color.opacity(0.16)` fill plus a 1pt stroke
// in the same color, so they read as soft chips that adapt to any accent.

/// A capsule chip — short status/category text on a tinted background.
struct Pill: View {
    let text: String
    var color: Color = Brand.accent

    var body: some View {
        Text(self.text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(self.color)
            .padding(.horizontal, Layout.spacing3)
            .padding(.vertical, 2)
            .background(Capsule().fill(self.color.opacity(0.16)))
            .overlay(Capsule().stroke(self.color.opacity(0.45), lineWidth: 1))
    }
}

/// A rounded-rectangle badge — like `Pill` but with squared corners, good for
/// counts or labels that sit flush against other rectangular content.
struct Badge: View {
    let text: String
    var color: Color = Brand.accent

    var body: some View {
        Text(self.text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(self.color)
            .padding(.horizontal, Layout.spacing2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                    .fill(self.color.opacity(0.16)))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                    .stroke(self.color.opacity(0.45), lineWidth: 1))
    }
}

/// A small colored status dot. Use the semantic level so it tracks system colors.
struct StatusDot: View {
    enum Level {
        case ok, warning, error

        var color: Color {
            switch self {
            case .ok: Color(nsColor: .systemGreen)
            case .warning: Color(nsColor: .systemOrange)
            case .error: Color(nsColor: .systemRed)
            }
        }
    }

    let level: Level

    init(_ level: Level) {
        self.level = level
    }

    var body: some View {
        Circle()
            .fill(self.level.color)
            .frame(width: 8, height: 8)
    }
}

/// A dot-plus-label tag: a `StatusDot`-sized circle followed by text, wrapped in a
/// soft rounded chip. Handy for labels that carry their own color.
struct Tag: View {
    let text: String
    var color: Color = Brand.accent

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(self.color)
                .frame(width: 6, height: 6)
            Text(self.text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, Layout.spacing2)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                .fill(self.color.opacity(0.16)))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                .stroke(self.color.opacity(0.45), lineWidth: 1))
    }
}
