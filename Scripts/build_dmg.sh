#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$ROOT/version.env"
# shellcheck source=/dev/null
source "$ROOT/Scripts/config.env"
if command -v node >/dev/null 2>&1; then
    APP_CONFIG_ENV=$(node "$ROOT/Scripts/lib/app_config.mjs" env "$ROOT/app.config.json")
    # shellcheck source=/dev/null
    source <(printf '%s\n' "$APP_CONFIG_ENV")
fi

APP=${1:-"$ROOT/.build/package/$APP_NAME.app"}
OUTPUT=${2:-"$ROOT/.build/artifacts/$APP_NAME-$MARKETING_VERSION.dmg"}
[[ -d "$APP" ]] || { echo "ERROR: app not found: $APP" >&2; exit 1; }

mkdir -p "$ROOT/.build" "$(dirname "$OUTPUT")"
STAGE=$(mktemp -d "$ROOT/.build/dmg-stage.XXXXXX")
cleanup() {
    rm -rf "$STAGE"
}
trap cleanup EXIT

ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUTPUT"
hdiutil create \
    -volname "$APP_DISPLAY" \
    -srcfolder "$STAGE" \
    -format UDZO \
    -ov \
    "$OUTPUT" >/dev/null

echo "$OUTPUT"
