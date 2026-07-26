#!/usr/bin/env bash
# Defensive helpers for locating Sparkle's signing tools and the nested
# components inside an embedded Sparkle.framework. Sourced by other scripts.
#
# Two public functions:
#   sparkle_find_tool <name>          -> prints the path to a Sparkle CLI tool
#                                        (sign_update / generate_appcast) found
#                                        under .build/artifacts, or fails.
#   sparkle_signing_targets <framework> -> prints the inside-out ordered list of
#                                        nested binaries/bundles to codesign.

# Locate a Sparkle-shipped tool (sign_update, generate_appcast) inside the SPM
# artifacts directory. Sparkle vends these as prebuilt binaries under
# .build/artifacts/<...>/Sparkle/bin/. Search defensively for layout drift.
sparkle_find_tool() {
    local tool="$1"
    local root="${2:-$PWD}"
    local candidate
    # Common, then fall back to a broad find.
    for candidate in \
        "$root"/.build/artifacts/sparkle/Sparkle/bin/"$tool" \
        "$root"/.build/artifacts/*/Sparkle/bin/"$tool" \
        "$root"/.build/artifacts/**/bin/"$tool"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    candidate=$(find "$root/.build/artifacts" -type f -name "$tool" -perm -u+x 2>/dev/null | head -n1 || true)
    if [[ -n "$candidate" && -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi
    echo "ERROR: Could not find Sparkle tool '$tool' under $root/.build/artifacts (build the app first to resolve Sparkle)." >&2
    return 1
}

# Resolve the active Sparkle framework version directory (Versions/Current, or
# the single concrete version dir).
sparkle_version_dir() {
    local sparkle="$1"
    local versions="$sparkle/Versions"
    if [[ ! -d "$versions" ]]; then
        echo "ERROR: Missing Sparkle Versions directory: $versions" >&2
        return 1
    fi
    if [[ -e "$versions/Current" ]]; then
        (cd "$versions/Current" && pwd -P)
        return 0
    fi
    local dirs=() d
    shopt -s nullglob
    for d in "$versions"/*; do
        [[ -d "$d" ]] && dirs+=("$d")
    done
    shopt -u nullglob
    if [[ ${#dirs[@]} -eq 1 ]]; then
        (cd "${dirs[0]}" && pwd -P)
        return 0
    fi
    echo "ERROR: Could not resolve a single Sparkle version dir under $versions" >&2
    return 1
}

# Emit the inside-out list of components to codesign for an embedded
# Sparkle.framework. Only existing paths are printed, so layout differences
# across Sparkle versions degrade gracefully.
sparkle_signing_targets() {
    local sparkle="$1"
    local vdir
    vdir=$(sparkle_version_dir "$sparkle") || return 1
    local candidates=(
        "$vdir/Autoupdate"
        "$vdir/Updater.app/Contents/MacOS/Updater"
        "$vdir/Updater.app"
        "$vdir/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
        "$vdir/XPCServices/Downloader.xpc"
        "$vdir/XPCServices/Installer.xpc/Contents/MacOS/Installer"
        "$vdir/XPCServices/Installer.xpc"
        "$vdir/Sparkle"
        "$sparkle"
    )
    local p
    for p in "${candidates[@]}"; do
        if [[ -e "$p" ]]; then
            printf '%s\n' "$p"
        fi
    done
}
