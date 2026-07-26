#!/usr/bin/env bash
# Dev loop: kill any running instance, build + package a debug .app, launch it,
# and verify it stays running. This is what `macos dev` runs.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

# shellcheck source=/dev/null
source "$ROOT/Scripts/config.env"
: "${APP_NAME:?config.env must set APP_NAME}"

PROCESS_PATTERN="$APP_NAME.app/Contents/MacOS/$APP_NAME"

log() { printf '%s\n' "$*" >&2; }
fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

# --- Kill any running instance -----------------------------------------------
log "==> Killing existing $APP_NAME instances"
for _ in {1..15}; do
    pkill -x "$APP_NAME" 2>/dev/null || true
    pkill -f "$PROCESS_PATTERN" 2>/dev/null || true
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1 && ! pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
        break
    fi
    sleep 0.2
done
# Force-kill stragglers so `open -n` cannot spawn a second instance.
pkill -9 -x "$APP_NAME" 2>/dev/null || true
pkill -9 -f "$PROCESS_PATTERN" 2>/dev/null || true

# --- Build + package debug ---------------------------------------------------
log "==> Packaging debug app"
APP=$("$ROOT/Scripts/package_app.sh" debug | tail -n1)
if [[ ! -d "$APP" ]]; then
    fail "package_app.sh did not produce an app bundle"
fi

# --- Launch ------------------------------------------------------------------
log "==> Launching $APP"
# Launch via LaunchServices so the process gets a proper bundle identity
# (menu bar item, single-instance, URL handlers). -g keeps focus on the editor.
open -n -g "$APP"

# --- Verify it stays running -------------------------------------------------
for _ in {1..15}; do
    if pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
        log "OK: $APP_NAME is running."
        exit 0
    fi
    sleep 0.4
done
fail "$APP_NAME exited immediately. Check Console.app (User Reports) for a crash log."
