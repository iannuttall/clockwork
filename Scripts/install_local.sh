#!/usr/bin/env bash
# Build and install a local ad-hoc signed Clockwork app and CLI.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$ROOT/Scripts/config.env"
: "${APP_NAME:?config.env must set APP_NAME}"

CLI_NAME="$(printf '%s' "$APP_NAME" | tr '[:upper:]' '[:lower:]')cli"
CLI_COMMAND="$(printf '%s' "$APP_NAME" | tr '[:upper:]' '[:lower:]')"
SOURCE="$ROOT/.build/package/$APP_NAME.app"
DESTINATION="/Applications/$APP_NAME.app"

"$ROOT/Scripts/package_app.sh" debug >/dev/null

echo "==> Closing development builds" >&2
pkill -x "$APP_NAME" 2>/dev/null || true
pkill -x Scheduler 2>/dev/null || true

echo "==> Installing $DESTINATION" >&2
rm -rf "$DESTINATION"
ditto "$SOURCE" "$DESTINATION"
xattr -cr "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"

mkdir -p "$HOME/.local/bin"
install -m 755 "$DESTINATION/Contents/MacOS/$CLI_NAME" "$HOME/.local/bin/$CLI_COMMAND"

echo "==> Launching installed $APP_NAME" >&2
open "$DESTINATION"
echo "$DESTINATION"
