#!/usr/bin/env bash
# Add or replace the current version in appcast.xml using Sparkle's EdDSA signature.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

ARTIFACT=${1:?"usage: $0 <path-to-signed-artifact>"}
[[ -f "$ARTIFACT" ]] || { echo "ERROR: artifact not found: $ARTIFACT" >&2; exit 1; }

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

: "${MARKETING_VERSION:?version.env must set MARKETING_VERSION}"
: "${BUILD_NUMBER:?version.env must set BUILD_NUMBER}"
: "${MIN_MACOS:?config.env must set MIN_MACOS}"
if [[ -n "${SPARKLE_PRIVATE_KEY_PATH:-}" && ! -f "$SPARKLE_PRIVATE_KEY_PATH" ]]; then
    echo "ERROR: Sparkle private key not found: $SPARKLE_PRIVATE_KEY_PATH" >&2
    exit 1
fi

APPCAST="$ROOT/appcast.xml"
CHANGELOG="$ROOT/CHANGELOG.md"
ARTIFACT_NAME=$(basename "$ARTIFACT")
ARTIFACT_LENGTH=$(stat -f%z "$ARTIFACT" 2>/dev/null || stat -c%s "$ARTIFACT")
if [[ -n "${DOWNLOAD_URL_PREFIX:-}" ]]; then
    DOWNLOAD_URL="${DOWNLOAD_URL_PREFIX%/}/v${MARKETING_VERSION}/${ARTIFACT_NAME}"
else
    : "${GH_OWNER:?config.env must set GH_OWNER when DOWNLOAD_URL_PREFIX is empty}"
    : "${GH_REPO:?config.env must set GH_REPO when DOWNLOAD_URL_PREFIX is empty}"
    DOWNLOAD_URL="https://github.com/${GH_OWNER}/${GH_REPO}/releases/download/v${MARKETING_VERSION}/${ARTIFACT_NAME}"
fi

GENERATE_KEYS=$(sparkle_find_tool generate_keys "$ROOT")
KEYCHAIN_PUBLIC_KEY=$("$GENERATE_KEYS" -p)
if [[ -z "${SPARKLE_PRIVATE_KEY_PATH:-}" && "$KEYCHAIN_PUBLIC_KEY" != "$SPARKLE_PUBLIC_KEY" ]]; then
    echo "ERROR: The Sparkle key in Keychain does not match app.config.json." >&2
    exit 1
fi

SIGN_UPDATE=$(sparkle_find_tool sign_update "$ROOT")
if [[ -n "${SPARKLE_PRIVATE_KEY_PATH:-}" ]]; then
    SIGN_OUTPUT=$("$SIGN_UPDATE" "$ARTIFACT" -f "$SPARKLE_PRIVATE_KEY_PATH")
else
    SIGN_OUTPUT=$("$SIGN_UPDATE" "$ARTIFACT")
fi
ED_SIGNATURE=$(printf '%s' "$SIGN_OUTPUT" | sed -E 's/.*edSignature="([^"]+)".*/\1/')
if [[ -z "$ED_SIGNATURE" || "$ED_SIGNATURE" == "$SIGN_OUTPUT" ]]; then
    echo "ERROR: Could not parse edSignature from sign_update output: $SIGN_OUTPUT" >&2
    exit 1
fi
SIGN_LENGTH=$(printf '%s' "$SIGN_OUTPUT" | sed -nE 's/.*length="([0-9]+)".*/\1/p')
[[ -z "$SIGN_LENGTH" ]] || ARTIFACT_LENGTH="$SIGN_LENGTH"

PUB_DATE=$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')
APPCAST="$APPCAST" \
CHANGELOG="$CHANGELOG" \
VERSION="$MARKETING_VERSION" \
BUILD="$BUILD_NUMBER" \
MIN_MACOS="$MIN_MACOS" \
DOWNLOAD_URL="$DOWNLOAD_URL" \
ED_SIGNATURE="$ED_SIGNATURE" \
ARTIFACT_LENGTH="$ARTIFACT_LENGTH" \
PUB_DATE="$PUB_DATE" \
APP_DISPLAY="${APP_DISPLAY:-App}" \
FEED_URL="${FEED_URL:-}" \
    node "$ROOT/Scripts/lib/appcast_update.mjs"

echo "Updated appcast.xml: ${MARKETING_VERSION} (build ${BUILD_NUMBER}) -> ${DOWNLOAD_URL}"
