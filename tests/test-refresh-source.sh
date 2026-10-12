#!/usr/bin/env bash
# Tests for scripts/refresh-source.sh. The upstream APT index is stubbed with
# file:// URLs via DEB_REPO_BASE.
#
# Usage: tests/test-refresh-source.sh
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT=$REPO/scripts/refresh-source.sh
pass=0 fail=0

ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1"; }
check() {  # name haystack needle
    if grep -qF -- "$3" <<<"$2"; then ok "$1"; else bad "$1"; echo "       expected: $3"; fi
}

# Build a workspace: stub APT repo, a manifest on stale pins, and a metainfo
# scaffold. $1/$2 = versions for the amd64/arm64 indexes.
make_work() {
    local work amd64_ver=$1 arm64_ver=$2
    work=$(mktemp -d)
    mkdir -p "$work/build-aux" \
             "$work/repo/dists/stable/main/binary-amd64" \
             "$work/repo/dists/stable/main/binary-arm64"

    # Two stanzas for amd64: an older version first, plus an unrelated package.
    # The parser has to filter by Package and pick the newest by version sort,
    # not by stanza order.
    cat > "$work/repo/dists/stable/main/binary-amd64/Packages" <<EOF
Package: claude-desktop
Version: 1.99.9
Architecture: amd64
Filename: pool/main/c/claude-desktop/claude-desktop_1.99.9_amd64.deb
Size: 111
SHA256: 1111111111111111111111111111111111111111111111111111111111111111

Package: claude-desktop-helper
Version: 99.0.0
Architecture: amd64
Filename: pool/main/c/claude-desktop-helper/claude-desktop-helper_99.0.0_amd64.deb
Size: 222
SHA256: 2222222222222222222222222222222222222222222222222222222222222222

Package: claude-desktop
Version: $amd64_ver
Architecture: amd64
Filename: pool/main/c/claude-desktop/claude-desktop_${amd64_ver}_amd64.deb
Size: 400000001
SHA256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
EOF
    cat > "$work/repo/dists/stable/main/binary-arm64/Packages" <<EOF
Package: claude-desktop
Version: $arm64_ver
Architecture: arm64
Filename: pool/main/c/claude-desktop/claude-desktop_${arm64_ver}_arm64.deb
Size: 400000002
SHA256: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
EOF

    # A decoy url: line inside x-checker-data guards the rewrite regex: only
    # a url directly followed by sha256 and size may be touched.
    cat > "$work/test.ClaudeDesktop.yaml" <<'EOF'
modules:
  - name: claude-desktop
    sources:
      - type: extra-data
        filename: claude-desktop.deb
        only-arches:
          - x86_64
        url: https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_0.0.0_amd64.deb
        sha256: 0000000000000000000000000000000000000000000000000000000000000000
        size: 1
        x-checker-data:
          type: rotating-url
          url: https://example.invalid/decoy/claude-desktop_amd64.deb
          is-main-source: true
      - type: extra-data
        filename: claude-desktop.deb
        only-arches:
          - aarch64
        url: https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_0.0.0_arm64.deb
        sha256: 0000000000000000000000000000000000000000000000000000000000000001
        size: 2
EOF

    cat > "$work/build-aux/test.metainfo.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>test</id>
  <releases>
    <release version="0.0.0" date="2026-08-14"/>
  </releases>
</component>
EOF
    echo "$work"
}

echo "refresh-source.sh"

# --- happy path: stale pins move to the newest versioned pool paths ----------
work=$(make_work 2.100.11111 2.100.11111)
out=$( cd "$work" && DEB_REPO_BASE="file://$work/repo" "$SCRIPT" test.ClaudeDesktop.yaml 2>&1 ) \
    || { bad "happy path exited non-zero"; printf '%s\n' "$out"; }
manifest=$(cat "$work/test.ClaudeDesktop.yaml")

check "x86_64 url is the versioned pool path" "$manifest" \
      "url: file://$work/repo/pool/main/c/claude-desktop/claude-desktop_2.100.11111_amd64.deb"
check "aarch64 url is the versioned pool path" "$manifest" \
      "url: file://$work/repo/pool/main/c/claude-desktop/claude-desktop_2.100.11111_arm64.deb"
check "x86_64 sha256 from the index"  "$manifest" "sha256: aaaaaaaa"
check "aarch64 sha256 from the index" "$manifest" "sha256: bbbbbbbb"
check "x86_64 size from the index"    "$manifest" "size: 400000001"
check "picked 2.100.11111 over 1.99.9 by version, not stanza order" "$out" \
      ">> upstream version: 2.100.11111"
check "x-checker-data url left untouched" "$manifest" \
      "url: https://example.invalid/decoy/claude-desktop_amd64.deb"
check "metainfo release updated" "$(cat "$work/build-aux/test.metainfo.xml")" \
      '<release version="2.100.11111"'

# url/sha256/size must stay adjacent: a regex that eats the preceding newline
# leaves blank lines that per-line greps and the idempotence check miss.
for a in amd64 arm64; do
    block=$(grep -A2 "claude-desktop_2.100.11111_$a.deb" "$work/test.ClaudeDesktop.yaml")
    if sed -n 2p <<<"$block" | grep -q '^ *sha256:' \
        && sed -n 3p <<<"$block" | grep -q '^ *size:'; then
        ok "$a url/sha256/size are adjacent lines"
    else
        bad "$a url/sha256/size are adjacent lines"; printf '%s\n' "$block"
    fi
done

# --- idempotence: a second run against the same index changes nothing --------
before=$(cat "$work/test.ClaudeDesktop.yaml")
( cd "$work" && DEB_REPO_BASE="file://$work/repo" "$SCRIPT" test.ClaudeDesktop.yaml ) >/dev/null 2>&1 \
    || bad "second run exited non-zero"
if [ "$before" = "$(cat "$work/test.ClaudeDesktop.yaml")" ]; then
    ok "re-run is a no-op on the manifest"
else
    bad "re-run is a no-op on the manifest"
fi
rm -rf "$work"

# --- disagreeing indexes: fail closed, write nothing -------------------------
work=$(make_work 2.100.11111 2.100.22222)
before=$(cat "$work/test.ClaudeDesktop.yaml")
if out=$( cd "$work" && DEB_REPO_BASE="file://$work/repo" "$SCRIPT" test.ClaudeDesktop.yaml 2>&1 ); then
    bad "disagreeing indexes must exit non-zero"
else
    ok "disagreeing indexes exit non-zero"
fi
check "and say which versions disagreed" "$out" "x86_64=2.100.11111 aarch64=2.100.22222"
if [ "$before" = "$(cat "$work/test.ClaudeDesktop.yaml")" ]; then
    ok "manifest untouched on disagreement"
else
    bad "manifest untouched on disagreement"
fi
check "metainfo untouched on disagreement" \
      "$(cat "$work/build-aux/test.metainfo.xml")" 'version="0.0.0"'
rm -rf "$work"

# --- invalid second stanza: preflight both, write nothing ---------------------
work=$(make_work 2.100.11111 2.100.11111)
arm_packages=$work/repo/dists/stable/main/binary-arm64/Packages
sed -i 's/^SHA256: b\{64\}$/SHA256: not-a-checksum/' "$arm_packages"
before_manifest=$(cat "$work/test.ClaudeDesktop.yaml")
before_metainfo=$(cat "$work/build-aux/test.metainfo.xml")
if out=$( cd "$work" && DEB_REPO_BASE="file://$work/repo" "$SCRIPT" test.ClaudeDesktop.yaml 2>&1 ); then
    bad "invalid arm64 checksum must exit non-zero"
else
    ok "invalid arm64 checksum exits non-zero"
fi
check "and reports invalid arm64 SHA256" "$out" "invalid SHA256 in arm64"
if [ "$before_manifest" = "$(cat "$work/test.ClaudeDesktop.yaml")" ]; then
    ok "manifest untouched when second stanza is invalid"
else
    bad "manifest untouched when second stanza is invalid"
fi
if [ "$before_metainfo" = "$(cat "$work/build-aux/test.metainfo.xml")" ]; then
    ok "metainfo untouched when second stanza is invalid"
else
    bad "metainfo untouched when second stanza is invalid"
fi
rm -rf "$work"

# The APT index is untrusted input. Reject a version containing shell syntax
# before either the manifest or metainfo is changed.
# The literal command substitution below is the test input.
# shellcheck disable=SC2016
bad_version='2.100.11111$(touch-PWNED)'
work=$(make_work "$bad_version" "$bad_version")
before_manifest=$(cat "$work/test.ClaudeDesktop.yaml")
if out=$( cd "$work" && DEB_REPO_BASE="file://$work/repo" "$SCRIPT" test.ClaudeDesktop.yaml 2>&1 ); then
    bad "unsafe upstream version must exit non-zero"
else
    ok "unsafe upstream version exits non-zero"
fi
check "and reports invalid Version" "$out" "invalid Version"
if [ "$before_manifest" = "$(cat "$work/test.ClaudeDesktop.yaml")" ]; then
    ok "manifest untouched for unsafe version"
else
    bad "manifest untouched for unsafe version"
fi
check "metainfo untouched for unsafe version" \
      "$(cat "$work/build-aux/test.metainfo.xml")" 'version="0.0.0"'
rm -rf "$work"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
