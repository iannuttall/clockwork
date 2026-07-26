import SwiftUI

// MARK: - Cards & Structure

/// A rounded translucent panel for grouping content. Wraps its `content` in
/// padding, a faint `.textBackgroundColor` fill, and a hairline separator stroke.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing4) {
            self.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.spacing4)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.35)))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

/// A small uppercase-weight header for a section of content inside a card or pane.
struct SectionHeader: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(self.title)
                .font(.subheadline.weight(.semibold))
            if let trailing {
                Spacer(minLength: Layout.spacing3)
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A hairline divider in the system separator color. Thin wrapper over `Divider`
/// that pins the color so it reads consistently on translucent backgrounds.
struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 0.5)
    }
}
