#!/usr/bin/env bash
# Sign (Developer ID, hardened runtime), notarize, and staple Scheduler.app, then
# produce the final distributable zip.
#
# Requires a release bundle built by package_app.sh (run it first, or this script
# will build one). Requires these env vars (exported by the orchestrator):
#   APP_IDENTITY   e.g. "Developer ID Application: Name (TEAMID)"
#   ASC_KEY_ID     App Store Connect API key id
#   ASC_ISSUER_ID  App Store Connect issuer id
#   ASC_KEY_PATH   path to the .p8 key file
#
# Echoes the final notarized zip path as the last line of stdout:
#   .build/artifacts/Scheduler-<MARKETING_VERSION>-universal.zip
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

# shellcheck source=/dev/null
source "$ROOT/version.env"
# shellcheck source=/dev/null
source "$ROOT/Scripts/config.env"
if command -v node >/dev/null 2>&1 && [[ -f "$ROOT/app.config.json" ]]; then
    APP_CONFIG_ENV=$(node "$ROOT/Scripts/lib/app_config.mjs" env "$ROOT/app.config.json")
    # shellcheck source=/dev/null
    source <(printf '%s\n' "$APP_CONFIG_ENV")
fi
# shellcheck source=/dev/null
source "$ROOT/Scripts/sparkle_paths.sh"

: "${APP_NAME:?config.env must set APP_NAME}"
: "${BUNDLE_ID:?config.env must set BUNDLE_ID}"
: "${MARKETING_VERSION:?version.env must set MARKETING_VERSION}"

: "${APP_IDENTITY:?Set APP_IDENTITY (Developer ID Application: Name (TEAMID))}"
: "${ASC_KEY_ID:?Set ASC_KEY_ID (App Store Connect key id)}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID (App Store Connect issuer id)}"
: "${ASC_KEY_PATH:?Set ASC_KEY_PATH (path to the .p8 key)}"

if [[ ! -f "$ASC_KEY_PATH" ]]; then
    echo "ERROR: ASC_KEY_PATH does not point at a file: $ASC_KEY_PATH" >&2
    exit 1
fi

CLI_NAME="$(printf '%s' "$APP_NAME" | tr '[:upper:]' '[:lower:]')cli"

# Build the release bundle if it does not already exist.
APP="$ROOT/.build/package/$APP_NAME.app"
if [[ ! -d "$APP" ]]; then
    echo "==> No release bundle found; building one" >&2
    APP=$("$ROOT/Scripts/package_app.sh" release | tail -n1)
fi
if [[ ! -d "$APP" ]]; then
    echo "ERROR: Release app bundle not found: $APP" >&2
    exit 1
fi

ARTIFACTS_DIR="$ROOT/.build/artifacts"
mkdir -p "$ARTIFACTS_DIR"

# --- Entitlements (hardened runtime, Developer ID; no app-sandbox) -----------
ENTITLEMENTS=$(mktemp "${TMPDIR:-/tmp}/${APP_NAME}-entitlements.XXXXXX.plist")
trap 'rm -f "$ENTITLEMENTS"' EXIT
cat > "$ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Developer ID distribution: hardened runtime, NO app-sandbox.
         Add narrow entitlements here only when the app actually needs them.

         If this app uses a shared app group (e.g. a widget), enable it here:
    <key>com.apple.security.application-groups</key>
    <array>
        <string>${TEAM_ID:-TEAMID}.${BUNDLE_ID}</string>
    </array>
    -->
</dict>
</plist>
PLIST

SIGN=(codesign --force --timestamp --options runtime --sign "$APP_IDENTITY")

echo "==> Signing with: $APP_IDENTITY" >&2

# Sign inside-out: Sparkle nested components, then the CLI helper, then the app.
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
    echo "==> Signing Sparkle components" >&2
    while IFS= read -r target; do
        [[ -n "$target" ]] && "${SIGN[@]}" "$target"
    done < <(sparkle_signing_targets "$SPARKLE_FW")
fi

if [[ -f "$APP/Contents/MacOS/$CLI_NAME" ]]; then
    "${SIGN[@]}" "$APP/Contents/MacOS/$CLI_NAME"
fi

echo "==> Signing app bundle" >&2
"${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP"

# --- Notarize ----------------------------------------------------------------
NOTARIZE_ZIP="$ARTIFACTS_DIR/${APP_NAME}-notarize.zip"
rm -f "$NOTARIZE_ZIP"
echo "==> Zipping for notarization" >&2
/usr/bin/ditto --norsrc -c -k --keepParent "$APP" "$NOTARIZE_ZIP"

echo "==> Submitting to notarytool (waits for result)" >&2
xcrun notarytool submit "$NOTARIZE_ZIP" \
    --key "$ASC_KEY_PATH" \
    --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" \
    --wait
rm -f "$NOTARIZE_ZIP"

echo "==> Stapling ticket" >&2
xcrun stapler staple "$APP"

# Re-strip xattrs before the final zip so no AppleDouble files sneak in.
xattr -cr "$APP"
find "$APP" -name '._*' -delete

FINAL_ZIP="$ARTIFACTS_DIR/${APP_NAME}-${MARKETING_VERSION}-universal.zip"
rm -f "$FINAL_ZIP"
echo "==> Creating final artifact" >&2
/usr/bin/ditto --norsrc -c -k --keepParent "$APP" "$FINAL_ZIP"

# --- dSYM ---------------------------------------------------------------------
DSYM="$ARTIFACTS_DIR/${APP_NAME}.dSYM"
DSYM_ZIP="${FINAL_ZIP%.zip}.dSYM.zip"
rm -rf "$DSYM" "$DSYM_ZIP"
if command -v dsymutil >/dev/null 2>&1; then
    echo "==> Creating dSYM" >&2
    dsymutil "$APP/Contents/MacOS/$APP_NAME" -o "$DSYM"
    if command -v dwarfdump >/dev/null 2>&1; then
        BIN_UUIDS=$(dwarfdump --uuid "$APP/Contents/MacOS/$APP_NAME" | awk '{print $2}' | sort | tr '\n' ' ')
        DSYM_UUIDS=$(dwarfdump --uuid "$DSYM" | awk '{print $2}' | sort | tr '\n' ' ')
        if [[ "$BIN_UUIDS" != "$DSYM_UUIDS" ]]; then
            echo "ERROR: dSYM UUIDs do not match app binary." >&2
            echo "       binary: $BIN_UUIDS" >&2
            echo "       dSYM:   $DSYM_UUIDS" >&2
            exit 1
        fi
    fi
    /usr/bin/ditto --norsrc -c -k --keepParent "$DSYM" "$DSYM_ZIP"
else
    echo "WARN: dsymutil not found; skipping dSYM artifact." >&2
fi

# --- Verify ------------------------------------------------------------------
echo "==> Verifying (spctl + stapler)" >&2
spctl -a -t exec -vv "$APP"
stapler validate "$APP"

echo "==> Done: $FINAL_ZIP" >&2
echo "$FINAL_ZIP"
