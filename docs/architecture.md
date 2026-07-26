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

The app is a no-dock agent (`LSUIElement`). SwiftUI exists only as a lifecycle host: the `App` scene
is a hidden 1×1 keepalive `WindowGroup` plus a `Settings` scene. Everything visible is AppKit:

- `AppDelegate` builds a `StatusItemController` (`@MainActor NSObject, NSMenuDelegate`).
- `StatusItemController` owns the `NSStatusItem` and a native `NSMenu`. Rich rows are SwiftUI views
  hosted in `NSMenuItem.view` via `NSHostingView` — native menu chrome, SwiftUI content.
- `MenuDescriptor` is a pure value type describing the menu (sections, entries, actions, SF Symbols).
  Both the AppKit builder and the SwiftUI card consume it, and it's unit-testable without AppKit.

Why AppKit and not `MenuBarExtra`: full control over the menu, keyboard handling, multiple status
items, and the option to draw the menu-bar icon itself (see the `icon-render` module).

## State

Modern Observation only. `SettingsStore` is an `@MainActor @Observable` over an **injected**
`UserDefaults` (not `@AppStorage`) so persistence is explicit and tests are isolated. Stores are
owned by the `App` via `@State` and passed down by constructor. No `ObservableObject`/`@StateObject`.

## Data flow

`StatusService` (in Core) produces an `AppStatus` value. The controller renders it through
`MenuDescriptor` into the menu. A real app replaces `StatusService.current()` with its actual source
(API, local computation, file) — keep that in Core and test it via `schedulercli`.

## Updates

`Updater.swift` wraps Sparkle behind `UpdaterProviding` with a `DisabledUpdaterController` no-op for
unsigned/dev builds, so update dialogs never fire during development. The feed is the committed
`appcast.xml` served from GitHub; see `docs/releasing.md`.
