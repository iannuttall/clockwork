---
summary: "How Scheduler is put together: targets, the menu bar, state, and data flow."
read_when:
  - Reviewing the architecture before feature work
  - Changing app lifecycle, the status item, or module boundaries
  - Deciding whether code belongs in Core or the app target
---

# Architecture

## Targets

Three SwiftPM targets, layered:

- **`SchedulerCore`** — portable domain logic (models, services, parsing). No AppKit; compiles on
  Linux. This is where business logic and anything worth testing lives.
- **`schedulercli`** — a thin executable over Core. Runs the same logic headlessly (`swift run
  schedulercli`), which is how Core gets exercised in tests and CI without an app bundle.
- **`Scheduler`** — the macOS app. Thin UI. Depends on Core. Links Sparkle (gated by `ENABLE_SPARKLE`).

The app bundle is assembled by `Scripts/package_app.sh`, not Xcode — SwiftPM can't emit `.app`
bundles, so the script generates `Info.plist`, lipo-merges arches, embeds `Sparkle.framework`, and
signs. There is no `.xcodeproj`.

## The menu bar

The app is a no-dock agent (`LSUIElement`). `AppDelegate` creates `PanelController`, which owns the
`NSStatusItem` and a borderless, keyable `NSPanel`. A persistent `NSHostingView` renders
`PanelContentView`; it is created once, has intrinsic sizing disabled, and scrolls inside a size the
controller chooses when the panel opens.

Opening the panel never performs disk or process work. It paints the model's warm snapshot first,
then asks `SchedulerModel` to refresh asynchronously. Global mouse monitoring dismisses it without
entering `NSMenu`'s blocking event-tracking loop. A native menu is used only for the status item's
small right-click context menu.

Why AppKit and not `MenuBarExtra`: the panel needs reliable keyboard focus, exact menu-bar anchoring,
explicit dismissal, and control over status-item badge drawing.

## State

Modern Observation only. `SettingsStore` and `SchedulerModel` are `@MainActor @Observable` types.
Stores are owned by the `App` via `@State` and passed down by constructor. No
`ObservableObject`/`@StateObject`.

`SchedulerModel` never performs repository or `launchctl` work on the main actor. Its frequent
refresh reads only task metadata and the latest run's small status files. Full stdout/stderr history
loads separately when an editor opens. Equal refreshes do not replace observable arrays, avoiding a
panel redraw every polling interval.

## Data flow

`TaskRepository` reads and writes task/run data. `SchedulerModel` moves those calls to utility tasks
and commits resulting `TaskSnapshot` values on the main actor. `PanelContentView` and the settings
window render the same snapshots. The CLI calls `SchedulerCore` directly.

## Updates

`Updater.swift` wraps Sparkle behind `UpdaterProviding` with a `DisabledUpdaterController` no-op for
unsigned/dev builds, so update dialogs never fire during development. The feed is the committed
`appcast.xml` served from GitHub; see `docs/releasing.md`.
