---
summary: "How Clockwork is split across Core, the CLI, the menu bar app, and launchd."
read_when:
  - Reviewing architecture before feature work
  - Changing app lifecycle, scheduling, storage, or module boundaries
---

# Architecture

## Targets

Clockwork has three SwiftPM targets:

- `ClockworkCore` owns schedules, task storage, launch-agent files, shell wrappers, run history, attention events, and legacy migration. It has no AppKit or SwiftUI dependency and builds on Linux.
- `clockworkcli` is a thin executable over Core. It reads and writes the same tasks as the app.
- `Clockwork` is the native menu bar app. It owns presentation, notifications, settings, and Sparkle.

SwiftPM builds executables, then `Scripts/package_app.sh` assembles the macOS bundle, merges `arm64` and `x86_64` slices, embeds Sparkle, compiles the Icon Composer project when present, and writes `Info.plist`.

## Scheduling and storage

Task definitions live in `~/Library/Application Support/Clockwork/tasks.json`. `LaunchAgentManager` writes one shell wrapper and one launch-agent plist per enabled task. `launchd` starts the wrapper, so Clockwork itself does not need to stay open.

Each run gets its own directory containing timestamps, stdout, stderr, exit status, and an optional attention event. A small `latest` pointer lets the menu refresh without reading every log. Wrappers retain the newest 50 run directories.

The first Clockwork run can move data from the private pre-release Scheduler build. The migration marker is kept until legacy jobs have been unloaded and all current jobs have been registered under the new Clockwork labels.

## Menu bar and state

`PanelController` owns the `NSStatusItem` and a persistent keyable `NSPanel` hosting SwiftUI. The controller fixes the panel size and position. The normal timer symbol is a template image; attention uses a separately drawn orange badge.

`ClockworkModel` is `@MainActor @Observable`, but repository and `launchctl` work runs in detached utility tasks. The panel renders a cached snapshot immediately, then refreshes asynchronously. Full log history loads only when a task is opened.

## Updates

`Updater.swift` wraps Sparkle behind `UpdaterProviding`. Debug bundles omit Sparkle feed metadata so local development never starts update checks. Public releases use the committed `appcast.xml`; see [Releasing](releasing.md).
