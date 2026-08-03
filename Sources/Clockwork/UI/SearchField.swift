import SwiftUI

/// A rounded search field: magnifier, a plain `TextField`, and a clear button that
/// appears once there's text. Use this when you want the search look inside a card
/// or list header; a bare `TextField().textFieldStyle(.roundedBorder)` is fine for
/// simpler cases.
struct SearchField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String = "Search", text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        HStack(spacing: Layout.spacing2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(self.placeholder, text: self.$text)
                .textFieldStyle(.plain)
            if !self.text.isEmpty {
                Button {
                    self.text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear")
            }
        }
        .padding(.horizontal, Layout.spacing3)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.controlRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}
