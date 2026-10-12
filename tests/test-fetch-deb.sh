#!/usr/bin/env bash
# Tests for scripts/fetch-deb.sh. Anthropic has no rolling URL, so the script
# resolves the newest version from the Packages index and then verifies the
# download against the index before caching it. Both halves are asserted here
# against a file:// stub repo. The script writes .cache/ next to itself, so it
# runs from a copy in a scratch tree, never against the real checkout.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
pass=0 fail=0

ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() {  # name actual expected
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected '$3', got '$2'"; fi
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A scratch checkout: just the two scripts, so `cd $(dirname $0)/..` lands here.
mkdir -p "$work/tree/scripts"
cp "$REPO/scripts/fetch-deb.sh" "$REPO/scripts/apt-index.sh" "$work/tree/scripts/"
SCRIPT=$work/tree/scripts/fetch-deb.sh

# Stub repo: two versions in the pool, listed oldest-first in the index.
pool=$work/repo/pool/main/c/claude-desktop
mkdir -p "$pool" "$work/repo/dists/stable/main/binary-amd64"
printf 'payload-old' > "$pool/claude-desktop_1.0.0_amd64.deb"
printf 'payload-new' > "$pool/claude-desktop_2.0.0_amd64.deb"
sha_old=$(sha256sum "$pool/claude-desktop_1.0.0_amd64.deb" | cut -d' ' -f1)
sha_new=$(sha256sum "$pool/claude-desktop_2.0.0_amd64.deb" | cut -d' ' -f1)

write_index() {  # write_index <sha-for-2.0.0>
    cat > "$work/repo/dists/stable/main/binary-amd64/Packages" <<EOF
Package: claude-desktop
Version: 1.0.0
Architecture: amd64
Filename: pool/main/c/claude-desktop/claude-desktop_1.0.0_amd64.deb
Size: 11
SHA256: $sha_old

Package: claude-desktop
Version: 2.0.0
Architecture: amd64
Filename: pool/main/c/claude-desktop/claude-desktop_2.0.0_amd64.deb
Size: 11
SHA256: $1
EOF
}

echo "fetch-deb.sh"

# --- resolves the newest version, downloads it, verifies, caches -------------
write_index "$sha_new"
out=$(DEB_REPO_BASE="file://$work/repo" "$SCRIPT" amd64 2>"$work/err") \
    || { bad "fetch exited non-zero"; cat "$work/err"; }
check "prints the version-keyed cache path" "$out" ".cache/claude-desktop_2.0.0_amd64.deb"
check "picked 2.0.0 over 1.0.0 by version, not stanza order" \
    "$(cat "$work/tree/.cache/claude-desktop_2.0.0_amd64.deb")" "payload-new"
check "no .part file left behind" \
    "$(find "$work/tree/.cache" -name '*.part' | wc -l)" "0"

# --- second run is a cache hit, not a download ------------------------------
out=$(DEB_REPO_BASE="file://$work/repo" "$SCRIPT" amd64 2>"$work/err") || bad "cache-hit run exited non-zero"
check "cache hit reports as such" "$(grep -c 'already cached' "$work/err")" "1"
check "cache hit returns the same path" "$out" ".cache/claude-desktop_2.0.0_amd64.deb"

# --- index sha disagrees with the pool bytes: refuse, cache nothing ----------
rm -rf "$work/tree/.cache"
write_index "0000000000000000000000000000000000000000000000000000000000000000"
if DEB_REPO_BASE="file://$work/repo" "$SCRIPT" amd64 >/dev/null 2>"$work/err"; then
    bad "mismatched sha256 must exit non-zero"
else
    ok "mismatched sha256 exits non-zero"
fi
check "and says why" "$(grep -c 'does not match the index' "$work/err")" "1"
check "nothing cached on mismatch" \
    "$( [ -e "$work/tree/.cache/claude-desktop_2.0.0_amd64.deb" ] && echo cached || echo absent )" "absent"
check "no .part file left on mismatch" \
    "$(find "$work/tree/.cache" -name '*.part' 2>/dev/null | wc -l)" "0"

# --- the version becomes a filename: reject path-traversal and shell syntax --
# A single-stanza index, so the hostile version is the one that gets selected.
# Alongside a sane 1.0.0 stanza, `sort -V` ranks '../../etc/passwd' lower and
# the script would correctly pick 1.0.0 and succeed, never reaching the
# validator this is meant to exercise.
# The literal substitution below is the test input.
# shellcheck disable=SC2016
for bad_version in '../../etc/passwd' '2.0.0$(touch PWNED)'; do
    cat > "$work/repo/dists/stable/main/binary-amd64/Packages" <<EOF
Package: claude-desktop
Version: $bad_version
Architecture: amd64
Filename: pool/main/c/claude-desktop/claude-desktop_2.0.0_amd64.deb
Size: 11
SHA256: $sha_new
EOF
    if DEB_REPO_BASE="file://$work/repo" "$SCRIPT" amd64 >/dev/null 2>"$work/err"; then
        bad "unsafe version '$bad_version' must exit non-zero"
    else
        ok "unsafe version '$bad_version' exits non-zero"
    fi
done
check "no PWNED file created" "$( [ -e "$work/tree/PWNED" ] && echo INJECTED || echo safe )" "safe"
check "nothing cached for an unsafe version" \
    "$(find "$work/tree/.cache" -name '*.deb' 2>/dev/null | wc -l)" "0"
write_index "$sha_new"

# --- an index with no claude-desktop stanza is a clear error -----------------
sed -i 's/^Package: claude-desktop$/Package: something-else/' "$work/repo/dists/stable/main/binary-amd64/Packages"
if DEB_REPO_BASE="file://$work/repo" "$SCRIPT" amd64 >/dev/null 2>"$work/err"; then
    bad "missing stanza must exit non-zero"
else
    ok "missing stanza exits non-zero"
fi
check "and names the package" "$(grep -c 'no claude-desktop stanza' "$work/err")" "1"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
