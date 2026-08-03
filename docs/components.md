---
summary: "The small SwiftUI component set used by Clockwork."
read_when:
  - Building or restyling menu and settings UI
  - Looking for an existing control or theme token
---

# Components

Clockwork's reusable SwiftUI pieces live in `Sources/Clockwork/UI`. They use system colors, controls, and SF Symbols so light mode, dark mode, accessibility, and menu highlighting continue to work.

## Brand and layout

`Brand.swift` owns the accent color, display name, and menu bar symbol. `Theme.swift` owns spacing, radii, fixed panel dimensions, badge sizing, and highlighted-row colors. Change these shared values instead of scattering constants through views.

## Controls

- `PrimaryButton`, `SecondaryButton`, and `CardIconButtonStyle` cover action hierarchy.
- `Dropdown` and `SegmentedControl` wrap the two selection styles used by the app.
- `SearchField` provides the standard searchable list field.
- `PreferenceToggleRow`, `LabeledRow`, and `SettingsSection` keep settings aligned.

## Presentation

- `Card`, `SectionHeader`, and `DividerLine` group task information.
- `Pill`, `Badge`, `Tag`, and `StatusDot` show compact state.
- `StatTile`, `MetricRow`, and `MeterBar` show run statistics.
- `LinkRow` and `ExternalLink` handle URLs with the app's hover and tint behavior.

Prefer native SwiftUI controls where one of these wrappers does not express the job. Menu bar images are AppKit-owned and must follow the template and orange attention badge rules in `AGENTS.md`.
