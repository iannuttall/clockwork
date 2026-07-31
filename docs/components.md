---
summary: "The SwiftUI component kit baked into the app (Sources/Scheduler/UI): buttons, selects, cards, pills, stats, links, and theming — with copy-paste snippets."
read_when:
  - Building or restyling any menu/settings UI
  - Looking for a ready-made control instead of writing one
  - Reskinning the app's accent, menu-bar symbol, or name
---

# Components

All components live in **`Sources/Scheduler/UI/`**. They're native SwiftUI over AppKit
semantic colors — no third-party deps, no `Material`, no custom fonts or color
assets — so they get free light/dark adaptation and match the system.

## How to reskin (edit Brand.swift)

`UI/Brand.swift` is the single reskin point. Change the accent, the menu-bar
symbol, and the display name there; every link, button, card tint, and the status
item follow:

```swift
enum Brand {
    static let accent: Color = .accentColor          // or a fixed brand Color
    static let statusSymbol: String = "gauge.with.dots.needle.50percent"
    static let displayName: String = "Scheduler"
}
```

`Theme.swift` holds the spacing/radius scale (`Layout`) and `MenuHighlightStyle`
(semantic colors that stay legible when a menu row is highlighted). Stick to the
`Layout` constants so things line up: spacing 4/6/8/10/12, radii 6/8/10, bar 6.

---

## Buttons

Prefer native styles; the wrappers just name intent. Add `.controlSize(.small)`
in menus/prefs.

- **PrimaryButton** — accent-tinted primary action.
- **SecondaryButton** — bordered secondary action.
- **CardIconButtonStyle** — pressed/scale style for compact icon buttons.

```swift
PrimaryButton("Save") { save() }
SecondaryButton("Cancel") { dismiss() }
Button("Delete", role: .destructive) { delete() }.buttonStyle(.bordered)
Button { star() } label: { Image(systemName: "star") }
    .buttonStyle(CardIconButtonStyle())
```

## Selects / Dropdowns

- **Dropdown** — styled `Menu` select (checkmark + chevron) that fires a closure.

```swift
Dropdown(
    options: MenuBarDisplayMode.allCases,
    selection: settings.displayMode,
    label: { $0.label },
    onSelect: { settings.displayMode = $0 })
```

Simple bound alternative — native `Picker`:

```swift
Picker("Interval", selection: $value) {
    ForEach(cases) { Text($0.label).tag($0) }
}
.pickerStyle(.menu).labelsHidden()
```

## Segmented

- **SegmentedControl** — thin wrapper over `Picker(.segmented)`.

```swift
SegmentedControl(options: Density.allCases, selection: $density, label: { $0.label })
    .frame(width: 200)
```

## Toggles

- **PreferenceToggleRow** — checkbox toggle with optional subtitle (prefs).

```swift
PreferenceToggleRow(
    title: "Launch at login",
    subtitle: "Start automatically when you log in.",
    isOn: $settings.launchAtLogin)
```

Use `Toggle(...).toggleStyle(.switch)` for an enable/disable switch.

## Text / Search

- **SearchField** — rounded container with magnifier + clear button.

```swift
SearchField("Search repositories", text: $query)
```

## Rows & Sections

- **SettingsSection** — titled group of rows; pair with `Form().formStyle(.grouped)`.
- **LabeledRow** — label left, control right (like `LabeledContent`).

```swift
SettingsSection(title: "Menu bar") {
    LabeledRow("Density") {
        SegmentedControl(options: Density.allCases, selection: $density, label: { $0.label })
    }
}
```

## Cards

- **Card** — rounded translucent panel.
- **SectionHeader** — semibold header with optional trailing text.
- **DividerLine** — hairline separator in the system color.

```swift
Card {
    SectionHeader("Summary", trailing: "now")
    MetricRow(title: "Status", value: "Healthy")
    DividerLine()
    MetricRow(title: "Uptime", value: "99.9%")
}
```

## Pills / Badges / Dots

- **Pill** — capsule chip (tinted 0.16 fill + stroke).
- **Badge** — rounded-rect chip for counts/labels.
- **Tag** — colored dot + label chip.
- **StatusDot** — 8pt dot: `.ok` green / `.warning` orange / `.error` red.

```swift
Pill(text: "Active")
Badge(text: "12", color: Color(nsColor: .systemOrange))
Tag(text: "swift", color: Color(nsColor: .systemBlue))
StatusDot(.ok)
```

## Stats & Meters

- **StatTile** — caption over semibold value (scales to fit). Lay out side by side.
- **MetricRow** — label left, value right, baseline-aligned.
- **MeterBar** — flat capsule meter (height 6), accent-tinted, 0…1.

```swift
HStack(spacing: 10) {
    StatTile(title: "Open", value: "128", emphasis: true)
    StatTile(title: "Closed", value: "1.2k")
}
MetricRow(title: "Requests", value: "4,096")
MeterBar(value: 0.62, tint: Brand.accent)
```

Native alternative for a standard bar: `ProgressView(value: 0.62).tint(Brand.accent)`.

## Links

- **LinkRow** — icon + label, underline-on-hover, opens a URL.
- **ExternalLink** — bare accent hyperlink.

```swift
LinkRow(icon: "globe", title: "Website", url: "https://example.com")
ExternalLink("Documentation", url: "https://example.com/docs")
```

## Icons

Use SF Symbols everywhere: `Image(systemName: "gearshape")`. For menu-bar status
images set `image.isTemplate = true` so the system tints them (see
`PanelController` / `Brand.statusSymbol`).

## Theming / Brand

- **Brand** — accent, `statusSymbol`, `displayName`. The reskin point.
- **Layout** — spacing (4/6/8/10/12) and radii (6/8/10), `barHeight` 6.
- **MenuHighlightStyle** — `primary/secondary/error/progressTrack/progressTint/
  selectionBackground(_ isHighlighted:)` over semantic NSColors. Read
  `@Environment(\.menuItemHighlighted)` in views hosted inside a menu row.

```swift
@Environment(\.menuItemHighlighted) private var isHighlighted
Text(value).foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
```

## Gallery

`UI/GalleryView.swift` renders every component once and is wired into the
**Components** preferences tab — launch with `macos dev scheduler` to see the kit.
It's a dev/reference surface; delete it and its tab when you ship your own UI.
