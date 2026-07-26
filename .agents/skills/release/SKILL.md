---
name: release-scheduler
description: Ship a signed, notarized, auto-updating release of Scheduler. Use when cutting a new version.
---

# Release Scheduler

One command does the whole pipeline: `macos release scheduler`. This skill is the checklist around it.

## Before releasing

1. **Finalize the changelog.** Move work from `## Unreleased` into a dated `## X.Y.Z - YYYY-MM-DD`
   section. Entries are user-facing prose — what someone notices, not internal churn. This text
   becomes the GitHub release notes and the Sparkle appcast description verbatim.
2. **Set the version.** `macos bump scheduler --version X.Y.Z` (or `macos bump scheduler` to bump just
   the build number). The build number must strictly increase — Sparkle compares on it.
3. **Clean tree.** Commit everything; the release refuses to run on a dirty working tree.
4. **Preview.** `macos release scheduler --dry-run` — it lists every step and flags anything missing.

## Release

```
macos release scheduler
```

It runs: preflight → `swift test` → build+sign+notarize+staple → GitHub release (zip + dSYM) →
EdDSA-signed appcast (committed + pushed) → Homebrew cask → bump build number. It's idempotent and
fail-fast; re-running after a fix is safe.

## After releasing — verify the chain

- The GitHub release exists with the zip asset.
- `appcast.xml` has the new `<item>` with an `sparkle:edSignature`.
- The enclosure URL returns 200 (`curl -I <url>`).
- `brew install --cask scheduler` (if a tap is configured) installs the new version.
- Install the previous build and confirm Sparkle offers + applies the update.

A release isn't done until that chain checks out.

## Rules

- Signing/notary creds come from `~/.config/macos` — never hardcode or commit them.
- If notarization fails, fix and re-run; don't ship an un-notarized build (Gatekeeper will block it).
