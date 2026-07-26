---
name: qa-scheduler
description: Build, launch, and verify Scheduler in the menu bar after a change. Confirms the running build is the one you just built.
---

# QA Scheduler

Use this to verify a change actually works in the real app.

## Loop

1. `make check` — format + lint + test. Fix everything it reports before going further.
2. Relaunch cleanly so you never validate a stale build:
   ```
   pkill -x Scheduler || pkill -f Scheduler.app || true
   macos dev scheduler
   ```
3. Confirm the build you're looking at is the one you just built:
   ```
   pgrep -af "Scheduler.app/Contents/MacOS/Scheduler"
   ```
4. Verify behavior:
   - The status item appears in the menu bar; clicking it opens the menu.
   - The menu rows reflect the current `AppStatus` (cross-check with `swift run schedulercli`).
   - Settings opens (menu → Settings, or ⌘,) and prefs persist across relaunch.

## Rules

- **Never trigger Keychain prompts.** Credentials use file storage in DEBUG. Keep
  `KeychainPromptSafetyAuditTests` green.
- If a test needs live network or a TTY, gate it behind an env var; don't make it run by default.
- Report what you observed (menu contents, log lines), not just "it works".
