#!/usr/bin/env bash
# Fetch the newest upstream .deb into .cache/ (gitignored) and print its path.
#
# Resolved through the Packages index because Anthropic publishes only
# versioned pool/ files. The cache is keyed by version, so a new upstream is a
# new file and an unchanged one costs a single index fetch. The download is
# checked against the index's sha256 and size before it is kept: a truncated
# ~180 MB transfer must never become the file `make hashes` or `make icons`
# read, or they would pin bytes nobody can reproduce.
#
# Usage: scripts/fetch-deb.sh [amd64|arm64]
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=scripts/apt-index.sh
. scripts/apt-index.sh

ARCH=${1:-amd64}
BASE=${DEB_REPO_BASE:-https://downloads.claude.ai/claude-desktop/apt/stable}
PKG=claude-desktop

stanza=$(apt_index_newest "$BASE" "$ARCH" "$PKG")
[ -n "$stanza" ] || {
    echo "fetch-deb: no $PKG stanza in the $ARCH Packages index at $BASE" >&2
    exit 1
}
read -r ver filename size sha256 extra <<<"$stanza"
apt_stanza_validate "$ARCH" "$PKG" "$ver" "$filename" "$size" "$sha256" "$extra"

OUT=".cache/${PKG}_${ver}_${ARCH}.deb"
mkdir -p .cache

verified() {  # verified <file>: size and sha256 agree with the index
    [ "$(stat -c %s "$1")" = "$size" ] \
        && [ "$(sha256sum "$1" | cut -d' ' -f1)" = "$sha256" ]
}

if [ -f "$OUT" ] && verified "$OUT"; then
    echo ">> $ARCH $ver already cached in $OUT" >&2
    echo "$OUT"
    exit 0
fi

echo ">> fetching $ARCH $ver (cached in $OUT)" >&2
tmp="$OUT.part"
curl -fsSL --retry 3 -o "$tmp" "$BASE/$filename" \
    || { rm -f "$tmp"; echo "fetch-deb: download failed for $BASE/$filename" >&2; exit 1; }
verified "$tmp" || {
    rm -f "$tmp"
    echo "fetch-deb: $filename does not match the index (size/sha256), refusing to cache it" >&2
    exit 1
}
mv -f "$tmp" "$OUT"
echo "$OUT"
