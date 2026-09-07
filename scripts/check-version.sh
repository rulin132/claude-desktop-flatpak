#!/bin/bash
# Verify that a release version is consistent across the repository.
#
# Checks that the version appears in:
#   - CHANGELOG.md            as "## [VERSION] - YYYY-MM-DD"
#   - the AppStream metainfo  as <release version="VERSION" date="..."/>
#
# Usage: scripts/check-version.sh 1.1.0

set -euo pipefail

VERSION="${1:-}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"
METAINFO="$REPO_ROOT/com.anthropic.Claude.metainfo.xml"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>" >&2
    exit 2
fi

VERSION="${VERSION#v}"
FAILED=0

echo "🔍 Checking release consistency for version $VERSION"
echo ""

# The version must look like SemVer, because the tag and the AppStream
# release entry both feed version comparisons in software centres.
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "❌ '$VERSION' is not a valid semantic version (expected X.Y.Z)"
    FAILED=1
else
    echo "✓ Version string is valid SemVer"
fi

if grep -q "^## \[$VERSION\] - " "$CHANGELOG"; then
    echo "✓ CHANGELOG.md has a dated section for $VERSION"
else
    echo "❌ CHANGELOG.md is missing a section: ## [$VERSION] - YYYY-MM-DD"
    FAILED=1
fi

if grep -q "<release version=\"$VERSION\"" "$METAINFO"; then
    echo "✓ Metainfo has a <release> entry for $VERSION"
else
    echo "❌ $(basename "$METAINFO") is missing: <release version=\"$VERSION\" date=\"...\"/>"
    echo "   Software centres show this entry as the release notes."
    FAILED=1
fi

# The newest metainfo release should be the one being tagged, otherwise
# software centres advertise a stale version.
NEWEST=$(grep -o '<release version="[^"]*"' "$METAINFO" | head -1 | cut -d'"' -f2)
if [ "$NEWEST" = "$VERSION" ]; then
    echo "✓ $VERSION is the newest <release> in the metainfo"
else
    echo "❌ Newest metainfo release is '$NEWEST', expected '$VERSION'"
    echo "   AppStream requires releases in reverse-chronological order."
    FAILED=1
fi

echo ""
if [ "$FAILED" -ne 0 ]; then
    echo "❌ Release checks failed. See RELEASING.md for the checklist."
    exit 1
fi

echo "✅ All release checks passed for $VERSION"
