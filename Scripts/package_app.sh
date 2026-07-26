#!/usr/bin/env bash
# Assemble Scheduler.app from SwiftPM build products (no Xcode project).
#
# Usage: Scripts/package_app.sh [release|debug]   (default: release)
#   release: universal (arm64 + x86_64), unsigned (sign-and-notarize.sh signs it).
#   debug:   host arch only, ad-hoc signed so it launches locally.
#
# Reads version.env (MARKETING_VERSION, BUILD_NUMBER) and Scripts/config.env.
# Echoes the final .app path as the last line of stdout.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

CONF=${1:-release}
CONF=$(printf '%s' "$CONF" | tr '[:upper:]' '[:lower:]')
case "$CONF" in
    release | debug) ;;
    *)
        echo "ERROR: Unsupported configuration: $1 (expected release or debug)" >&2
        exit 1
        ;;
esac

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
: "${APP_DISPLAY:?config.env must set APP_DISPLAY}"
: "${BUNDLE_ID:?config.env must set BUNDLE_ID}"
: "${MIN_MACOS:?config.env must set MIN_MACOS}"
: "${MARKETING_VERSION:?version.env must set MARKETING_VERSION}"
: "${BUILD_NUMBER:?version.env must set BUILD_NUMBER}"
if [[ "$CONF" == "release" ]]; then
    : "${FEED_URL:?app.config.json must set feedURL before a release build}"
    : "${SPARKLE_PUBLIC_KEY:?app.config.json must set sparklePublicKey before a release build}"
fi

CLI_NAME="$(printf '%s' "$APP_NAME" | tr '[:upper:]' '[:lower:]')cli"

# --- Architectures -----------------------------------------------------------
if [[ "$CONF" == "release" ]]; then
    ARCH_LIST=(arm64 x86_64)
else
    case "$(uname -m)" in
        arm64) ARCH_LIST=(arm64) ;;
        x86_64) ARCH_LIST=(x86_64) ;;
        *) ARCH_LIST=("$(uname -m)") ;;
    esac
fi

swift_bin_path() {
    local arch="$1"
    swift build --show-bin-path -c "$CONF" --arch "$arch"
}

# --- Build + snapshot each arch's products -----------------------------------
# SwiftBuild may reuse one output dir across sequential per-arch builds, so copy
# each arch's binaries out before the next build can overwrite them.
STAGE_ROOT="$ROOT/.build/package-products/$CONF"
rm -rf "$STAGE_ROOT"

for ARCH in "${ARCH_LIST[@]}"; do
    echo "==> swift build -c $CONF --arch $ARCH" >&2
    swift build -c "$CONF" --arch "$ARCH"
    swift build -c "$CONF" --arch "$ARCH" --product "$CLI_NAME"
    bin_dir=$(swift_bin_path "$ARCH")
    stage="$STAGE_ROOT/$ARCH"
    mkdir -p "$stage"
    for name in "$APP_NAME" "$CLI_NAME"; do
        if [[ ! -f "$bin_dir/$name" ]]; then
            echo "ERROR: Missing build product '$name' for $ARCH at $bin_dir" >&2
            exit 1
        fi
        cp "$bin_dir/$name" "$stage/$name"
    done
done

# Preferred bin dir (first arch) holds Sparkle.framework + SwiftPM resource bundles.
PREFERRED_BIN_DIR=$(swift_bin_path "${ARCH_LIST[0]}")

# --- Assemble the .app -------------------------------------------------------
APP="$ROOT/.build/package/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

# Install a universal (lipo) or single-arch binary into the bundle.
install_binary() {
    local name="$1" dest="$2"
    local srcs=()
    local a
    for a in "${ARCH_LIST[@]}"; do
        srcs+=("$STAGE_ROOT/$a/$name")
    done
    if [[ ${#srcs[@]} -gt 1 ]]; then
        lipo -create "${srcs[@]}" -output "$dest"
    else
        cp "${srcs[0]}" "$dest"
    fi
    chmod +x "$dest"
}

install_binary "$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
install_binary "$CLI_NAME" "$APP/Contents/MacOS/$CLI_NAME"

# Copy SwiftPM resource bundles emitted next to the built binary (e.g. *.bundle).
shopt -s nullglob
for bundle in "$PREFERRED_BIN_DIR"/*.bundle; do
    cp -R "$bundle" "$APP/Contents/Resources/"
done
shopt -u nullglob

# Copy app-level resources, if the source target ships any.
if [[ -d "$ROOT/Sources/$APP_NAME/Resources" ]]; then
    cp -R "$ROOT/Sources/$APP_NAME/Resources/." "$APP/Contents/Resources/" 2>/dev/null || true
fi

# Convert Icon.icon (IconStudio) -> Icon.icns when present, then install it.
if [[ -d "$ROOT/Icon.icon" ]] && command -v iconutil >/dev/null 2>&1; then
    iconutil --convert icns --output "$ROOT/Icon.icns" "$ROOT/Icon.icon" 2>/dev/null || true
fi
if [[ -f "$ROOT/Icon.icns" ]]; then
    cp "$ROOT/Icon.icns" "$APP/Contents/Resources/Icon.icns"
fi

# --- Info.plist --------------------------------------------------------------
PLIST="$APP/Contents/Info.plist"
BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")

if [[ "$CONF" == "release" ]]; then
    FEED_URL_VALUE="${FEED_URL:-}"
    SPARKLE_KEY_VALUE="${SPARKLE_PUBLIC_KEY:-}"
    AUTO_CHECKS="true"
else
    FEED_URL_VALUE=""
    SPARKLE_KEY_VALUE=""
    AUTO_CHECKS="false"
fi

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_DISPLAY}</string>
    <key>CFBundleDisplayName</key><string>${APP_DISPLAY}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
    <key>LSUIElement</key><true/>
    <key>LSMultipleInstancesProhibited</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>BuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    <key>GitCommit</key><string>${GIT_COMMIT}</string>
PLIST

if [[ "$CONF" == "release" ]]; then
    cat >> "$PLIST" <<PLIST
    <key>SUFeedURL</key><string>${FEED_URL_VALUE}</string>
    <key>SUPublicEDKey</key><string>${SPARKLE_KEY_VALUE}</string>
    <key>SUEnableAutomaticChecks</key><${AUTO_CHECKS}/>
PLIST
fi

cat >> "$PLIST" <<PLIST
</dict>
</plist>
PLIST

# --- Embed Sparkle.framework -------------------------------------------------
SPARKLE_SRC="$PREFERRED_BIN_DIR/Sparkle.framework"
if [[ -d "$SPARKLE_SRC" ]]; then
    echo "==> Embedding Sparkle.framework" >&2
    cp -R "$SPARKLE_SRC" "$APP/Contents/Frameworks/"
    chmod -R a+rX "$APP/Contents/Frameworks/Sparkle.framework"
    # SwiftPM links Sparkle via @rpath; add the standard app framework rpath.
    install_name_tool -add_rpath "@executable_path/../Frameworks" \
        "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true
else
    echo "WARN: Sparkle.framework not found at $SPARKLE_SRC (auto-update disabled in this build)." >&2
fi

# --- Hygiene -----------------------------------------------------------------
chmod -R u+w "$APP"
# Strip extended attributes to avoid AppleDouble (._*) files that break sealing.
xattr -cr "$APP"
find "$APP" -name '._*' -delete

# --- Signing -----------------------------------------------------------------
# debug: ad-hoc sign so the app launches locally.
# release: leave unsigned; sign-and-notarize.sh handles Developer ID signing.
if [[ "$CONF" == "debug" ]]; then
    echo "==> Ad-hoc signing (debug)" >&2
    if [[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]]; then
        while IFS= read -r target; do
            [[ -n "$target" ]] && codesign --force --sign - "$target" || true
        done < <(sparkle_signing_targets "$APP/Contents/Frameworks/Sparkle.framework")
    fi
    codesign --force --sign - "$APP/Contents/MacOS/$CLI_NAME" || true
    codesign --force --sign - --deep "$APP"
fi

echo "==> Built $APP" >&2
echo "$APP"
