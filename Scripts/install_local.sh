#!/usr/bin/env bash
# Build and install a local ad-hoc signed Scheduler app.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$ROOT/.build/package/Scheduler.app"
DESTINATION="/Applications/Scheduler.app"

"$ROOT/Scripts/package_app.sh" debug >/dev/null

echo "==> Closing the development build" >&2
pkill -x Scheduler 2>/dev/null || true

echo "==> Installing $DESTINATION" >&2
mkdir -p "$DESTINATION"
ditto "$SOURCE" "$DESTINATION"
xattr -cr "$DESTINATION"

SIGN_IDENTITY=${LOCAL_SIGN_IDENTITY:-}
if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
        | head -1)
fi
if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> Signing with $SIGN_IDENTITY" >&2
    codesign --force --deep --sign "$SIGN_IDENTITY" "$DESTINATION"
fi

mkdir -p "$HOME/.local/bin"
install -m 755 "$DESTINATION/Contents/MacOS/schedulercli" "$HOME/.local/bin/scheduler"

echo "==> Launching installed Scheduler" >&2
open "$DESTINATION"
echo "$DESTINATION"
