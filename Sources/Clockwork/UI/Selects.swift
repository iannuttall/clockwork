import SwiftUI

// MARK: - Selects

//
// For a plain bound selection, native `Picker` is the simplest path:
//
//   Picker("Interval", selection: $value) { ForEach(cases) { Text($0.label).tag($0) } }
//       .pickerStyle(.menu).labelsHidden()
//
// `Dropdown` is the styled action-menu variant (checkmark + chevron label) used
// when you want a flat control that fires a closure rather than binding a value.

/// A styled `Menu`-based select: a flat chevron control that lists `options`,
/// marks the current one with a checkmark, and calls `onSelect` when chosen.
struct Dropdown<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let label: (Option) -> String
    let onSelect: (Option) -> Void

    var body: some View {
        Menu {
            ForEach(self.options, id: \.self) { option in
                Button {
                    self.onSelect(option)
                } label: {
                    if option == self.selection {
                        Label(self.label(option), systemImage: "checkmark")
                    } else {
                        Text(self.label(option))
                    }
                }
            }
        } label: {
            HStack(spacing: Layout.spacing2) {
                Text(self.label(self.selection))
                    .lineLimit(1)
                Spacer(minLength: Layout.spacing1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Layout.spacing4)
            .frame(height: 24)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: Layout.controlRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Thin wrapper over a segmented `Picker`. Binds `selection` and renders each
/// option's `label`.
struct SegmentedControl<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    init(
        options: [Option],
        selection: Binding<Option>,
        label: @escaping (Option) -> String)
    {
        self.options = options
        self._selection = selection
        self.label = label
    }

    var body: some View {
        Picker("", selection: self.$selection) {
            ForEach(self.options, id: \.self) { option in
                Text(self.label(option)).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
