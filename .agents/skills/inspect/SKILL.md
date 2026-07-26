---
name: inspect-scheduler
description: Read-only inspection of Scheduler — config, version, and current status. Never mutates config, credentials, or releases.
---

# Inspect Scheduler

Use this to answer "what is the app's current state" without changing anything.

## Rules

- **Read-only.** Never edit `app.config.json`, `version.env`, credentials, or run a release.
- Never print secrets. Signing/notary material is not in this repo; do not read `~/.config/macos/secrets`.

## What to read

- Identity & distribution: `app.config.json`.
- Version: `version.env` (`MARKETING_VERSION`, `BUILD_NUMBER`).
- Headless status (no app bundle needed): `swift run schedulercli` — prints the app's current
  `AppStatus` as JSON. This is the fastest way to see what the menu would show.
- Released versions: `appcast.xml` (each `<item>` is a shipped build).
- Compliance: `macos audit scheduler`.

## Don't

- Don't launch the app to inspect it — use `schedulercli`.
- Don't run `swift test`/`make check` here; that's the qa skill.
