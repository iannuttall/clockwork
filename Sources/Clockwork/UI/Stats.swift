import SwiftUI

// MARK: - Stats & Meters

/// A KPI tile: a small caption over a semibold value that scales down to fit.
/// Lay several side by side in an `HStack`/`LazyVGrid` for a stat row.
struct StatTile: View {
    let title: String
    let value: String
    var emphasis: Bool = false
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(self.title)
                .font(.caption2)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(1)
            Text(self.value)
                .font(self.emphasis ? .headline : .subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A label on the left and a value on the right, baseline-aligned. The plain-text
/// counterpart to `LabeledRow` for read-only metric lines.
struct MetricRow: View {
    let title: String
    let value: String
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(self.title)
                .font(.footnote)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            Spacer(minLength: Layout.spacing3)
            Text(self.value)
                .font(.footnote)
                .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                .lineLimit(1)
        }
    }
}

/// A flat capsule progress meter (height 6). For a standard control, native
/// `ProgressView(value:total:).tint(…)` works too; this version honors menu
/// highlighting and a tint threshold so it fits inside menu cards.
struct MeterBar: View {
    /// 0…1 fill fraction.
    let value: Double
    var tint: Color = Brand.accent
    @Environment(\.menuItemHighlighted) private var isHighlighted

    private var clamped: Double {
        min(1, max(0, self.value))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MenuHighlightStyle.progressTrack(self.isHighlighted))
                Capsule()
                    .fill(MenuHighlightStyle.progressTint(self.isHighlighted, fallback: self.tint))
                    .frame(width: proxy.size.width * self.clamped)
            }
            .clipped()
        }
        .frame(height: Layout.barHeight)
        .accessibilityElement()
        .accessibilityValue("\(Int((self.clamped * 100).rounded())) percent")
    }
}
