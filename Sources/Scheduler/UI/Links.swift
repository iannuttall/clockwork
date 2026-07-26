import AppKit
import SwiftUI

// MARK: - Links

/// An icon + label row that opens a URL, underlining the label on hover. The
/// accent-colored "About" link style from the reference apps.
@MainActor
struct LinkRow: View {
    let icon: String
    let title: String
    let url: String

    @State private var hovering = false

    var body: some View {
        Button {
            if let url = URL(string: self.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: Layout.spacing2) {
                Image(systemName: self.icon)
                Text(self.title)
                    .underline(self.hovering, color: Brand.accent)
            }
            .foregroundStyle(Brand.accent)
            .padding(.vertical, Layout.spacing1)
        }
        .buttonStyle(.plain)
        .onHover { self.hovering = $0 }
    }
}

/// A bare text hyperlink that opens a URL — no icon, accent-colored.
@MainActor
struct ExternalLink: View {
    let title: String
    let url: String

    init(_ title: String, url: String) {
        self.title = title
        self.url = url
    }

    var body: some View {
        Button(self.title) {
            if let url = URL(string: self.url) {
                NSWorkspace.shared.open(url)
            }
        }
        .buttonStyle(.link)
        .tint(Brand.accent)
    }
}
