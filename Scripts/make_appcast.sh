#!/usr/bin/env bash
# Add (or replace) the current version's <item> in appcast.xml using Sparkle's
# EdDSA signature for the signed zip.
#
# Usage: Scripts/make_appcast.sh <path-to-signed-zip>
# Requires env SPARKLE_PRIVATE_KEY_PATH (path to the Sparkle EdDSA private key).
#
# Reads version.env (MARKETING_VERSION, BUILD_NUMBER) and Scripts/config.env
# (MIN_MACOS, GH_OWNER, GH_REPO, FEED_URL). The enclosure download URL is built
# as: https://github.com/<owner>/<repo>/releases/download/v<version>/<zip name>.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

ZIP=${1:?"usage: $0 <path-to-signed-zip>"}
if [[ ! -f "$ZIP" ]]; then
    echo "ERROR: zip not found: $ZIP" >&2
    exit 1
fi

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

: "${MARKETING_VERSION:?version.env must set MARKETING_VERSION}"
: "${BUILD_NUMBER:?version.env must set BUILD_NUMBER}"
: "${MIN_MACOS:?config.env must set MIN_MACOS}"
: "${SPARKLE_PRIVATE_KEY_PATH:?Set SPARKLE_PRIVATE_KEY_PATH (Sparkle EdDSA private key)}"

if [[ ! -f "$SPARKLE_PRIVATE_KEY_PATH" ]]; then
    echo "ERROR: SPARKLE_PRIVATE_KEY_PATH does not point at a file: $SPARKLE_PRIVATE_KEY_PATH" >&2
    exit 1
fi

APPCAST="$ROOT/appcast.xml"
CHANGELOG="$ROOT/CHANGELOG.md"
ZIP_NAME=$(basename "$ZIP")
ZIP_LENGTH=$(stat -f%z "$ZIP" 2>/dev/null || stat -c%s "$ZIP")
if [[ -n "${DOWNLOAD_URL_PREFIX:-}" ]]; then
    DOWNLOAD_URL="${DOWNLOAD_URL_PREFIX%/}/v${MARKETING_VERSION}/${ZIP_NAME}"
else
    : "${GH_OWNER:?config.env must set GH_OWNER when DOWNLOAD_URL_PREFIX is empty}"
    : "${GH_REPO:?config.env must set GH_REPO when DOWNLOAD_URL_PREFIX is empty}"
    DOWNLOAD_URL="https://github.com/${GH_OWNER}/${GH_REPO}/releases/download/v${MARKETING_VERSION}/${ZIP_NAME}"
fi

# --- EdDSA signature ---------------------------------------------------------
SIGN_UPDATE=$(sparkle_find_tool sign_update "$ROOT")
# sign_update prints e.g.:  sparkle:edSignature="..." length="12345"
SIGN_OUTPUT=$("$SIGN_UPDATE" "$ZIP" -f "$SPARKLE_PRIVATE_KEY_PATH")
ED_SIGNATURE=$(printf '%s' "$SIGN_OUTPUT" | sed -E 's/.*edSignature="([^"]+)".*/\1/')
if [[ -z "$ED_SIGNATURE" || "$ED_SIGNATURE" == "$SIGN_OUTPUT" ]]; then
    echo "ERROR: Could not parse edSignature from sign_update output: $SIGN_OUTPUT" >&2
    exit 1
fi
# Prefer the length sign_update reports (matches what it signed) when available.
SIGN_LENGTH=$(printf '%s' "$SIGN_OUTPUT" | sed -nE 's/.*length="([0-9]+)".*/\1/p')
if [[ -n "$SIGN_LENGTH" ]]; then
    ZIP_LENGTH="$SIGN_LENGTH"
fi

# --- Update appcast.xml via a small node helper ------------------------------
PUB_DATE=$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')

APPCAST="$APPCAST" \
CHANGELOG="$CHANGELOG" \
VERSION="$MARKETING_VERSION" \
BUILD="$BUILD_NUMBER" \
MIN_MACOS="$MIN_MACOS" \
DOWNLOAD_URL="$DOWNLOAD_URL" \
ED_SIGNATURE="$ED_SIGNATURE" \
ZIP_LENGTH="$ZIP_LENGTH" \
PUB_DATE="$PUB_DATE" \
APP_DISPLAY="${APP_DISPLAY:-App}" \
FEED_URL="${FEED_URL:-}" \
    node "$ROOT/Scripts/lib/appcast_update.mjs"

echo "Updated appcast.xml: ${MARKETING_VERSION} (build ${BUILD_NUMBER}) -> ${DOWNLOAD_URL}"
