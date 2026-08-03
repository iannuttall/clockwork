---
summary: "How Clockwork is built, signed, notarized, published, and updated."
read_when:
  - Cutting a release
  - Debugging signing, notarization, the appcast, or Sparkle
---

# Releasing

Clockwork is distributed directly as a signed and notarized DMG. Sparkle installs updates from GitHub Releases. There is no Mac App Store build.

## Required setup

The Mac making a release needs:

- a Developer ID Application certificate available to `codesign`
- a saved `notarytool` profile or an App Store Connect API key
- the Sparkle private key matching the public key in `app.config.json`, preferably in Keychain
- the final Icon Composer project at `Resources/AppIcon.icon`

Clockwork can use the same `portmanager` notarization profile and Sparkle keychain key as Natter and Portman. Confirm both before the first release:

```sh
xcrun notarytool history --keychain-profile portmanager
.build/artifacts/sparkle/Sparkle/bin/generate_keys -p
```

The second command must print the public key stored in `app.config.json`.

Export the release identity and profile without committing them:

```sh
export APP_IDENTITY='Developer ID Application: Iancredible Ltd (JXNCT3BEVQ)'
export NOTARY_PROFILE=portmanager
```

`SIGN_IDENTITY` is accepted as an alias for `APP_IDENTITY`. The scripts also support the file-based `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`, and `SPARKLE_PRIVATE_KEY_PATH` variables when a separate release environment needs them.

## Build and sign

Before releasing, set `MARKETING_VERSION` and the increasing `BUILD_NUMBER` in `version.env`. Move the user-facing changes into a dated version section in `CHANGELOG.md`, then run:

```sh
make check
make release
```

`make release` builds a fresh universal app, signs Sparkle and the bundled CLI inside-out, enables the hardened runtime, verifies a real launch, creates and signs the DMG, submits it to Apple's notary service, staples the result, runs Gatekeeper checks, and writes a SHA-256 checksum beside it.

The final files are:

```text
.build/artifacts/Clockwork-X.Y.Z.dmg
.build/artifacts/Clockwork-X.Y.Z.dmg.sha256
```

## Publish and update Sparkle

Create a draft GitHub release tagged `vX.Y.Z` and upload both files. Keep it as a draft while the appcast is updated:

```sh
gh release create vX.Y.Z \
  .build/artifacts/Clockwork-X.Y.Z.dmg \
  .build/artifacts/Clockwork-X.Y.Z.dmg.sha256 \
  --draft \
  --title "Clockwork X.Y.Z" \
  --notes-file RELEASE_NOTES.md
```

Update the appcast using the exact DMG attached to that draft:

```sh
make appcast ARTIFACT=.build/artifacts/Clockwork-X.Y.Z.dmg
```

The appcast command verifies the keychain public key, signs the DMG with Sparkle's EdDSA key, adds its size and download URL, and uses the matching changelog section for release notes. Commit and push `appcast.xml` after checking it, then publish the draft release:

```sh
gh release edit vX.Y.Z --draft=false
```

This order prevents the public update feed from pointing at an artifact that is not available yet.

## Final checks

- The GitHub release contains the DMG and checksum.
- The checksum matches the downloaded DMG.
- `appcast.xml` contains the new build number and `sparkle:edSignature`.
- The enclosure URL returns the DMG.
- A previous installed build offers and completes the update.

Do not ship if any signing, notarization, Gatekeeper, or update check fails.
