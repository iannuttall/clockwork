---
name: release-clockwork
description: Build and verify a signed, notarized, auto-updating Clockwork release.
---

# Release Clockwork

## Preflight

1. Move user-facing changes into a dated `## X.Y.Z - YYYY-MM-DD` section in `CHANGELOG.md`.
2. Set the matching `MARKETING_VERSION` and a strictly increasing `BUILD_NUMBER` in `version.env`.
3. Confirm `Resources/AppIcon.icon` contains the final artwork.
4. Confirm the Developer ID identity, `notarytool` profile, and Sparkle keychain key described in `docs/releasing.md` are available.
5. Run `make check` and commit the clean release state.

## Build

Run `make release`. Do not run individual signing or notarization commands by hand.

The command creates:

- `.build/artifacts/Clockwork-X.Y.Z.dmg`
- `.build/artifacts/Clockwork-X.Y.Z.dmg.sha256`

## Publish

Upload both files to a draft GitHub release tagged `vX.Y.Z`, then run:

```sh
make appcast ARTIFACT=.build/artifacts/Clockwork-X.Y.Z.dmg
```

Review and commit `appcast.xml`, then publish the draft release. Verify the GitHub download, checksum, appcast signature, and an update from the previous installed build. Never commit private keys or ship an unnotarized artifact.
