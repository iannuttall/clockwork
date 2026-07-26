#!/usr/bin/env bash
# Validate that CHANGELOG.md is ready to release:
#   - the top "## " section is NOT "Unreleased" and IS dated (YYYY-MM-DD)
#   - its version matches MARKETING_VERSION in version.env
#
# Exits non-zero with a clear message on any violation.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

# shellcheck source=/dev/null
source "$ROOT/version.env"
: "${MARKETING_VERSION:?version.env must set MARKETING_VERSION}"

CHANGELOG="$ROOT/CHANGELOG.md"
if [[ ! -f "$CHANGELOG" ]]; then
    echo "ERROR: CHANGELOG.md not found at $CHANGELOG" >&2
    exit 1
fi

# The first "## " heading after a pinned bare "## Unreleased" working section.
# We tolerate the pinned "## Unreleased" header (used to stage in-flight changes)
# but the first VERSIONED section must be the release and must be dated.
TOP=""
while IFS= read -r heading; do
    heading=$(printf '%s' "$heading" | sed 's/^##[[:space:]]*//')
    # Skip a pinned bare "Unreleased" heading.
    if printf '%s' "$heading" | grep -qiE '^unreleased[[:space:]]*$'; then
        continue
    fi
    TOP="$heading"
    break
done < <(grep '^## ' "$CHANGELOG")

if [[ -z "$TOP" ]]; then
    echo "ERROR: No versioned '## ' section found in CHANGELOG.md" >&2
    exit 1
fi

if printf '%s' "$TOP" | grep -qi 'unreleased'; then
    echo "ERROR: Top CHANGELOG version section is still labeled 'Unreleased': '$TOP'" >&2
    echo "       Finalize it as '## ${MARKETING_VERSION} - $(date +%F)' before releasing." >&2
    exit 1
fi

# Expect "<version> - <YYYY-MM-DD>".
TOP_VERSION=$(printf '%s' "$TOP" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
if [[ "$TOP_VERSION" != "$MARKETING_VERSION" ]]; then
    echo "ERROR: Top CHANGELOG version '$TOP_VERSION' != version.env MARKETING_VERSION '$MARKETING_VERSION'" >&2
    exit 1
fi

if ! printf '%s' "$TOP" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
    echo "ERROR: Top CHANGELOG section '$TOP' is undated (expected 'YYYY-MM-DD')." >&2
    exit 1
fi

echo "Changelog OK for ${MARKETING_VERSION}: ${TOP}"
