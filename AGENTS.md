# Repository Guidelines

Scheduler is a native macOS menu bar app: SwiftPM (no Xcode project), AppKit
`NSStatusItem` + a keyable `NSPanel` hosting SwiftUI, distributed Developer-ID-direct
with Sparkle auto-update. This file is the contract for human and AI contributors. Read it before
making changes.

## Project structure

- `Sources/SchedulerCore/` — portable domain logic (models, services). Compiles on Linux; no AppKit.
- `Sources/schedulercli/` — a headless CLI over Core, so logic is testable without an app bundle.
- `Sources/Scheduler/` — the macOS app (thin UI). `SchedulerApp.swift` is the `@main` entry;
  `PanelController.swift` owns the status item and panel, and `PanelContentView.swift` renders it.
- `Tests/SchedulerCoreTests/` (macOS) and `Tests/SchedulerCoreLinuxTests/` (the portable subset).
- `Scripts/` — build/sign/notarize/appcast tooling. Prefer these over raw `swift`/`codesign`.
- `app.config.json` — identity, distribution, feed URL. Single source of truth for app metadata.

## Build, test, run

- `macos dev scheduler` (or `make dev`) — build, ad-hoc sign, launch into the menu bar. The dev loop.
- `swift test` (or `make test`) — run the suite (Swift Testing).
- `make check` — format + lint + test. **Run this after any change and fix everything it reports.**
- `macos release scheduler` — full release; never hand-run the signing steps.

## Coding style

- Run `swiftformat Sources Tests` and `swiftlint --strict`. 4-space indent, ~120-col lines.
- **Explicit `self` is intentional** (Swift 6 concurrency) — do not strip it.
- Modern Observation only: `@Observable` models with `@State` ownership and `@Bindable` in views.
  Do **not** use `ObservableObject`, `@ObservedObject`, or `@StateObject`.
- Prefer modern macOS 14+ APIs over deprecated counterparts. Keep files small (<~500 lines); split
  large `@MainActor` types into `Type+Concern.swift` extensions.
- Put business/parse logic in `SchedulerCore` (and cover it with a test) — keep the app target thin.

## Testing

- Swift Testing (`import Testing`, `@Test`, `#expect`/`#require`, backtick names). Suites are structs.
- Test Core via the library or the CLI — avoid tests that need a running app bundle.
- New behavior in Core needs a test; a Linux-safe test goes in `SchedulerCoreLinuxTests`.

## Agent notes (operational rules — read these)

- **Validate the build you think you're validating.** After changing app code, relaunch cleanly:
  `pkill -x Scheduler || pkill -f Scheduler.app || true; macos dev scheduler`. A copy from another checkout
  can look identical in the menu bar — confirm with `pgrep -af "Scheduler.app/Contents/MacOS/Scheduler"`.
- **Never trigger Keychain prompts in tests or checks.** The credential store uses file storage in
  DEBUG for exactly this reason. Use stubs/test stores; never call UI-prompting `SecItem*` from tests.
  (`KeychainPromptSafetyAuditTests` enforces this — keep it green.)
- **Don't add dependencies or tooling without confirmation.** This app ships Foundation + Sparkle.
- **Don't commit secrets.** Signing/notary/Sparkle material lives in `~/.config/macos`, never here.
- Keep `app.config.json` authoritative; if you change identity/distribution, update it (the CLI and
  `Scripts/config.env` read from it).

## Commits & PRs

Conventional commits (`feat:`, `fix:`, `chore:`). One logical change per commit. The top
`CHANGELOG.md` section is user-facing release-notes prose — update it for anything users notice; it
feeds the GitHub release and the Sparkle appcast verbatim.
