#!/bin/bash
# Print the CHANGELOG.md section for a given version.
#
# Usage: scripts/extract-release-notes.sh 1.1.0

set -euo pipefail

VERSION="${1:-}"
CHANGELOG="${2:-$(dirname "$0")/../CHANGELOG.md}"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version> [changelog-path]" >&2
    exit 2
fi

# Strip a leading "v" so both "v1.1.0" and "1.1.0" work.
VERSION="${VERSION#v}"

if [ ! -f "$CHANGELOG" ]; then
    echo "❌ Changelog not found: $CHANGELOG" >&2
    exit 1
fi

# Print everything between "## [VERSION]" and the next "## " heading.
NOTES=$(awk -v version="$VERSION" '
    $0 ~ "^## \\[" version "\\]" { found = 1; next }
    found && /^## / { exit }
    found { print }
' "$CHANGELOG")

# Trim leading and trailing blank lines.
NOTES=$(printf '%s\n' "$NOTES" | sed -e '/./,$!d' | tac | sed -e '/./,$!d' | tac)

if [ -z "$NOTES" ]; then
    echo "❌ No changelog section found for version $VERSION" >&2
    echo "   Expected a heading like: ## [$VERSION] - YYYY-MM-DD" >&2
    exit 1
fi

printf '%s\n' "$NOTES"
