#!/usr/bin/env bash
# Re-pin the manifest from upstream's APT index: url, sha256 and size for both
# arches come from dists/stable/main/binary-*/Packages.
#
# Usage: scripts/refresh-source.sh [manifest.yaml]
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/apt-index.sh
. "$SCRIPT_DIR/apt-index.sh"
BASE=${DEB_REPO_BASE:-https://downloads.claude.ai/claude-desktop/apt/stable}
PKG=claude-desktop

manifests=(./*.ClaudeDesktop.yaml)
MANIFEST=${1:-${manifests[0]}}

declare -A ARCHES=([x86_64]=amd64 [aarch64]=arm64)
declare -A STANZAS=()
declare -A VERSIONS=()
declare -A FILENAMES=()
declare -A SIZES=()
declare -A SHA256S=()

# Read both indexes before writing anything: the arches publish separately and
# can briefly disagree, and a mixed pin must never reach the manifest.
for arch in x86_64 aarch64; do
    deb_arch=${ARCHES[$arch]}
    stanza=$(apt_index_newest "$BASE" "$deb_arch" "$PKG")
    [ -n "$stanza" ] || {
        echo "refresh-source: no $PKG stanza in the $deb_arch Packages index" >&2
        exit 1
    }
    STANZAS[$arch]=$stanza
done
# Validate and parse every stanza before changing either repository file. A
# bad second architecture must not leave the first source block half-updated.
for arch in x86_64 aarch64; do
    deb_arch=${ARCHES[$arch]}
    read -r ver filename size sha256 extra <<<"${STANZAS[$arch]}"
    apt_stanza_validate "$deb_arch" "$PKG" "$ver" "$filename" "$size" "$sha256" "$extra"
    VERSIONS[$arch]=$ver
    FILENAMES[$arch]=$filename
    SIZES[$arch]=$size
    SHA256S[$arch]=$sha256
done

ver_x86=${VERSIONS[x86_64]}
ver_arm=${VERSIONS[aarch64]}
if [ "$ver_x86" != "$ver_arm" ]; then
    echo "refresh-source: indexes disagree: x86_64=$ver_x86 aarch64=$ver_arm" >&2
    echo "refresh-source: upstream is likely mid-publish, retry later" >&2
    exit 1
fi

for arch in x86_64 aarch64; do
    deb_arch=${ARCHES[$arch]}
    ver=${VERSIONS[$arch]}
    filename=${FILENAMES[$arch]}
    size=${SIZES[$arch]}
    sha256=${SHA256S[$arch]}
    echo ">> $arch: $ver  sha256=$sha256 size=$size"

    python3 - "$MANIFEST" "$deb_arch" "$BASE/$filename" "$sha256" "$size" <<'PY'
import re, sys
manifest, deb_arch, url, sha, size = sys.argv[1:6]
text = open(manifest).read()

# Match the url line directly followed by sha256 and size, so an url inside
# x-checker-data can never match. [ \t] not \s for the indent: \s also eats
# the preceding newline and leaves blank lines between the rewritten fields.
pattern = re.compile(
    r'^([ \t]*)url:\s*\S*_' + re.escape(deb_arch) + r'\.deb\n'
    r'[ \t]*sha256:\s*\S+\n'
    r'[ \t]*size:\s*\d+\n', re.M)

def repl(m):
    i = m.group(1)
    return f"{i}url: {url}\n{i}sha256: {sha}\n{i}size: {size}\n"

text, n = pattern.subn(repl, text, count=1)
if n != 1:
    sys.exit(f"refresh-source: could not locate the {deb_arch} source block")
open(manifest, 'w').write(text)
PY
done

echo ">> upstream version: $ver_x86"
"$SCRIPT_DIR/sync-version.sh" "$ver_x86"

echo ">> done. Review the diff before committing."
