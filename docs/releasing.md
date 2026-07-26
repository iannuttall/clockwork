---
summary: "How a release is built, signed, notarized, and published — and how auto-update works."
read_when:
  - Cutting a release
  - Debugging notarization, the appcast, or Sparkle updates
  - Setting up signing on a new machine
---

# Releasing

Releases are **Developer ID direct**: a signed, notarized `.zip` distributed via GitHub Releases,
auto-updated by Sparkle, and installable with `brew install --cask`. There is no Mac App Store build
in v1 (`app.config.json` carries `distribution` for the future MAS path).

## One-time setup

`macos signing setup` configures everything (Developer ID cert, App Store Connect API key for
notarization, Sparkle EdDSA keys, Homebrew tap). `macos doctor` verifies it. Secrets live in
`~/.config/macos`, never in this repo.

## Cutting a release

```
# 1. finalize CHANGELOG.md (date the top section)
macos bump scheduler --version X.Y.Z      # or: macos bump scheduler   (build only)
git commit -am "release X.Y.Z"
macos release scheduler                    # the whole pipeline
```

`macos release` runs: preflight (identity, notary, sparkle, gh, clean tree, dated changelog, version
unused) → `swift test` → `Scripts/sign-and-notarize.sh` (build universal, sign inside-out with
hardened runtime, `notarytool submit --wait`, `stapler staple`, verify) → GitHub release with the zip
+ dSYM → `Scripts/make_appcast.sh` (EdDSA-sign, embed changelog HTML, commit + push `appcast.xml`) →
Homebrew cask → bump build number. Fail-fast and idempotent; fix and re-run.

## How auto-update works

`Info.plist` carries `SUFeedURL` (the committed `appcast.xml`, served from GitHub raw) and
`SUPublicEDKey`. Sparkle polls the feed, compares on `sparkle:version` (the build number), and
verifies each download against the EdDSA signature. The private key lives only in
`~/.config/macos/secrets` — losing it means you can't ship updates the existing installs will accept,
so back it up.

## Verifying a release

A release isn't done until: the GitHub release has the zip; `appcast.xml` has the new `<item>` with
an `edSignature`; `curl -I` on the enclosure returns 200; and installing the previous build then
checking for updates actually offers and applies the new one.

## Build numbers

`version.env` holds `MARKETING_VERSION` (SemVer, user-visible) and `BUILD_NUMBER` (monotonic int,
what Sparkle compares). The build number must strictly increase every release; `macos release` bumps
it after publishing.
