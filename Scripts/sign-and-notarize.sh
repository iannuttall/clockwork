#!/usr/bin/env bash
# Build, Developer ID sign, notarize, staple, and verify the Clockwork DMG.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

# shellcheck source=/dev/null
source "$ROOT/version.env"
# shellcheck source=/dev/null
source "$ROOT/Scripts/config.env"
if command -v node >/dev/null 2>&1; then
    APP_CONFIG_ENV=$(node "$ROOT/Scripts/lib/app_config.mjs" env "$ROOT/app.config.json")
    # shellcheck source=/dev/null
    source <(printf '%s\n' "$APP_CONFIG_ENV")
fi
# shellcheck source=/dev/null
source "$ROOT/Scripts/sparkle_paths.sh"

"$ROOT/Scripts/validate_changelog.sh"

# Natter and Portman use SIGN_IDENTITY, while the shared macOS scripts use
# APP_IDENTITY. Accept both so this app can use the same release environment.
APP_IDENTITY="${APP_IDENTITY:-${SIGN_IDENTITY:-}}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

: "${APP_NAME:?config.env must set APP_NAME}"
: "${MARKETING_VERSION:?version.env must set MARKETING_VERSION}"
: "${APP_IDENTITY:?Set APP_IDENTITY or SIGN_IDENTITY to a Developer ID Application identity}"
if [[ -z "$NOTARY_PROFILE" ]]; then
    : "${ASC_KEY_ID:?Set NOTARY_PROFILE or ASC_KEY_ID}"
    : "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID when using an API key}"
    : "${ASC_KEY_PATH:?Set ASC_KEY_PATH when using an API key}"
    [[ -f "$ASC_KEY_PATH" ]] || {
        echo "ERROR: App Store Connect key not found: $ASC_KEY_PATH" >&2
        exit 1
    }
fi
[[ -n "${SPARKLE_PUBLIC_KEY:-}" ]] || { echo "ERROR: Set the Sparkle public key before release." >&2; exit 1; }
[[ -d "$ROOT/Resources/AppIcon.icon" ]] || {
    echo "ERROR: Add the final Icon Composer project at Resources/AppIcon.icon before release." >&2
    exit 1
}
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "ERROR: Quit every running copy of $APP_NAME before making a release." >&2
    exit 1
fi

APP=$("$ROOT/Scripts/package_app.sh" release | tail -n1)
CLI_NAME="$(printf '%s' "$APP_NAME" | tr '[:upper:]' '[:lower:]')cli"
SIGN=(codesign --force --timestamp --options runtime --sign "$APP_IDENTITY")

echo "==> Signing with $APP_IDENTITY" >&2
if [[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]]; then
    while IFS= read -r target; do
        [[ -n "$target" ]] && "${SIGN[@]}" "$target"
    done < <(sparkle_signing_targets "$APP/Contents/Frameworks/Sparkle.framework")
fi
"${SIGN[@]}" "$APP/Contents/MacOS/$CLI_NAME"
"${SIGN[@]}" "$APP"

codesign --verify --deep --strict "$APP"
SIGN_INFO=$(codesign -d --verbose=2 "$APP" 2>&1 || true)
[[ "$SIGN_INFO" == *"flags="*"runtime"* ]] || {
    echo "ERROR: Hardened runtime is missing from the signed app." >&2
    exit 1
}

LAUNCH_PID=""
cleanup_launch() {
    if [[ -n "$LAUNCH_PID" ]] && kill -0 "$LAUNCH_PID" 2>/dev/null; then
        kill "$LAUNCH_PID" 2>/dev/null || true
    fi
}
trap cleanup_launch EXIT
"$APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 &
LAUNCH_PID=$!
sleep 5
if kill -0 "$LAUNCH_PID" 2>/dev/null; then
    kill "$LAUNCH_PID"
    wait "$LAUNCH_PID" 2>/dev/null || true
    LAUNCH_PID=""
else
    wait "$LAUNCH_PID" 2>/dev/null || true
    echo "ERROR: The signed app exited during its launch check." >&2
    exit 1
fi

ARTIFACTS="$ROOT/.build/artifacts"
mkdir -p "$ARTIFACTS"
DMG="$ARTIFACTS/$APP_NAME-$MARKETING_VERSION.dmg"
CHECKSUM="$DMG.sha256"
"$ROOT/Scripts/build_dmg.sh" "$APP" "$DMG" >/dev/null

codesign --force --timestamp --sign "$APP_IDENTITY" "$DMG"
if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
else
    xcrun notarytool submit "$DMG" \
        --key "$ASC_KEY_PATH" \
        --key-id "$ASC_KEY_ID" \
        --issuer "$ASC_ISSUER_ID" \
        --wait
fi
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

SHA256=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
printf '%s  %s\n' "$SHA256" "$(basename "$DMG")" > "$CHECKSUM"

echo "$DMG"
echo "$CHECKSUM"
