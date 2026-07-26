#!/usr/bin/env bash
# Thin wrapper around swiftformat + swiftlint. Both tools are required so CI
# cannot pass without actually enforcing format and lint rules.
#
# Usage: Scripts/lint.sh [lint|format]
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

cmd="${1:-lint}"

have() { command -v "$1" >/dev/null 2>&1; }

run_format_lint() {
    have swiftformat || {
        echo "ERROR: swiftformat not installed." >&2
        exit 1
    }
    have swiftlint || {
        echo "ERROR: swiftlint not installed." >&2
        exit 1
    }
    swiftformat Sources Tests --lint
    swiftlint --strict
}

case "$cmd" in
    lint)
        run_format_lint
        ;;
    format)
        if have swiftformat; then
            swiftformat Sources Tests
        else
            echo "ERROR: swiftformat not installed." >&2
            exit 1
        fi
        ;;
    *)
        echo "Usage: $(basename "$0") [lint|format]" >&2
        exit 2
        ;;
esac
