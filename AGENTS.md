# Repository guidelines

Clockwork is a native macOS menu bar app for scheduling recurring commands with `launchd`. It uses Swift 6.2, SwiftPM, AppKit for the status item and panel, SwiftUI for content, and Sparkle for direct updates. There is no Xcode project.

Read this file before changing anything. The rules below include product contracts and bugs that are easy to reintroduce.

## Project structure

- `Sources/ClockworkCore/` contains portable schedules, storage, launch-agent generation, run history, and migration logic. It must not import AppKit or SwiftUI.
- `Sources/clockworkcli/` contains the headless CLI over Core.
- `Sources/Clockwork/` contains the macOS app. The UI stays thin and sends disk and `launchctl` work to Core off the main actor.
- `Tests/ClockworkCoreTests/` contains macOS tests. `Tests/ClockworkCoreLinuxTests/` contains the portable subset used by Linux CI.
- `Scripts/` contains build, install, DMG, Developer ID signing, notarization, and appcast tools.
- `app.config.json` is the source of truth for public app identity. `version.env` owns version numbers.

## Build, test, and run

- `make dev` builds an app bundle, ad-hoc signs it, launches it, and verifies the process stays alive.
- `make check` formats, lints, and runs tests. Run it after every source change.
- `swift test` runs the Swift Testing suite.
- `make package` builds an unsigned universal release bundle.
- `make dmg` wraps the universal bundle in a local test DMG.
- `make release` signs, notarizes, staples, and creates the final DMG and checksum. Do not run signing steps by hand.

## Code style

- Run SwiftFormat and SwiftLint through `make check`.
- Four-space indentation and explicit `self` are intentional.
- Use `@Observable`, `@State`, and `@Bindable`. Do not add Combine observation types.
- Core behavior needs a pure test. UI types should stay thin.
- Comments explain a scheduling, launchd, concurrency, or UI constraint, not the line below them.

## Product contracts and traps

**launchd owns scheduled execution.** A task must keep running when Clockwork is closed. Do not replace launch agents with an in-app timer.

**The panel opens from a warm snapshot.** Disk reads, run-history parsing, wrapper generation, and `launchctl` calls must stay off the main actor. Opening the panel must not block on them.

**The panel owns its size.** Do not use intrinsic hosting-view sizing. Live task changes would move the panel away from the menu bar.

**The timer is a template image.** Set `isTemplate` on the final normal-state `NSImage`. Do not set `contentTintColor`. Both details are required for light and dark menu bars.

**Attention has one orange badge.** Draw the timer in `labelColor` and the badge in `systemOrange` inside a deferred image handler. The badged image cannot be a template. Leave `contentTintColor` nil.

**Attention is explicit.** A nonzero exit code is a failure, not an attention event. Only the event file or `clockwork attention` creates the orange badge and notification. Notify once per run and preserve acknowledgement until a newer event appears.

**Shell input must stay quoted.** Task names and working directories are user input. Keep wrapper generation in Core, quote paths safely, use atomic status files, and retain no more than the latest 50 runs.

**Every changed launch agent must be reconciled.** Save, enable, disable, and delete operations must update both task storage and the corresponding launch agent. Never leave an old enabled job behind after changing its schedule.

**The Scheduler migration is one-time and retryable.** Existing private pre-release data moves from `Application Support/Scheduler`. Old `com.iannuttall.scheduler.task.*` jobs are removed only after the data move, and the marker remains until every Clockwork job is registered successfully.

**The old Scheduler app must be closed before migration.** Clockwork asks the private pre-release app to terminate before starting its first refresh. Dev and install scripts also close it. Otherwise the old process can recreate jobs while their files are moving.

**Development builds do not run Sparkle.** Debug packaging leaves the feed and public key out on purpose. Public release builds require the final icon, feed URL, and public key.

**Never trigger a Keychain prompt in tests.** Do not add `SecItem*` calls to test paths. `KeychainPromptSafetyAuditTests` enforces this rule.

## Verification

After app changes run `make check`, then `make dev`. Confirm the exact bundle is running:

```sh
pgrep -af "Clockwork.app/Contents/MacOS/Clockwork"
```

Inspect shared state through the bundled CLI:

```sh
.build/package/Clockwork.app/Contents/MacOS/clockworkcli list --json
```

For packaging changes, run `make package`, verify both bundled executables contain `arm64` and `x86_64`, then run `make dmg` and `hdiutil verify` on the result. A compile alone is not proof that the app bundle launches or that `launchd` accepted a job.

## Commits and releases

Use conventional commits such as `feat:`, `fix:`, and `chore:`. Update `CHANGELOG.md` for anything a user notices. Never commit certificates, App Store Connect keys, Sparkle private keys, or values from `~/.config/macos`.
