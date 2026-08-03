import SwiftUI

// MARK: - Rows & Sections

/// A titled group of settings rows. Pair with `Form`/`.formStyle(.grouped)`.
struct SettingsSection<Content: View>: View {
    let title: String?
    let caption: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing4) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 14) {
                self.content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A checkbox toggle with an optional subtitle (preferences convention).
struct PreferenceToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: self.$isOn) {
                Text(self.title).font(.body)
            }
            .toggleStyle(.checkbox)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A label on the left and a trailing control on the right, like `LabeledContent`
/// but with a baked-in layout. Drop any control into the `content` builder.
struct LabeledRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(self.title)
            Spacer(minLength: Layout.spacing5)
            self.content
        }
    }
}
