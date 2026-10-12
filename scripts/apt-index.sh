# shellcheck shell=bash
# Resolve the newest stanza for a package from an APT Packages index.
#
# Anthropic's repository has no rolling "latest" alias: every .deb lives at a
# versioned pool/ path and the index is the only thing that says which one is
# current. scripts/fetch-deb.sh and scripts/refresh-source.sh both resolve
# through here so they cannot disagree about what "newest" means.

# apt_index_newest <repo-base-url> <deb-arch> <package>
#   stdout: "version filename size sha256" for the highest version, or nothing
#   if the index has no complete stanza for that package. An index may list
#   several versions, so pick by version sort, not stanza order.
apt_index_newest() {
    local base=$1 deb_arch=$2 pkg=$3
    curl -fsSL "$base/dists/stable/main/binary-$deb_arch/Packages" \
    | awk -v RS= -v FS='\n' -v want="Package: $pkg" '{
        v = f = s = h = ""; is_pkg = 0
        for (i = 1; i <= NF; i++) {
            if ($i == want)                         is_pkg = 1
            else if (index($i, "Version: ")  == 1)  v = substr($i, 10)
            else if (index($i, "Filename: ") == 1)  f = substr($i, 11)
            else if (index($i, "Size: ")     == 1)  s = substr($i, 7)
            else if (index($i, "SHA256: ")   == 1)  h = substr($i, 9)
        }
        if (is_pkg && v != "" && f != "" && s != "" && h != "") print v, f, s, h
    }' | sort -V | tail -n 1
}

# apt_stanza_validate <deb-arch> <package> <version> <filename> <size> <sha256> [extra]
#   APT metadata is external input. The version becomes a cache filename, a
#   git tag and an Actions output, and the filename becomes a URL, so accept
#   only the grammar each field requires. Non-zero exit with a message on
#   stderr for the first field that fails.
apt_stanza_validate() {
    local deb_arch=$1 pkg=$2 ver=$3 filename=$4 size=$5 sha256=$6 extra=${7:-}
    local tag=${0##*/}

    [ -z "$extra" ] || {
        echo "$tag: malformed $deb_arch Packages stanza" >&2
        return 1
    }
    [[ "$ver" =~ ^[0-9][-0-9A-Za-z.+:~]{0,127}$ ]] || {
        echo "$tag: invalid Version in $deb_arch Packages index" >&2
        return 1
    }
    [[ "$filename" =~ ^pool/main/${pkg:0:1}/${pkg}/${pkg}_[-0-9A-Za-z.+:~%]+_${deb_arch}\.deb$ ]] || {
        echo "$tag: invalid Filename in $deb_arch Packages index" >&2
        return 1
    }
    [[ "$size" =~ ^[1-9][0-9]*$ ]] || {
        echo "$tag: invalid Size in $deb_arch Packages index" >&2
        return 1
    }
    [[ "$sha256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
        echo "$tag: invalid SHA256 in $deb_arch Packages index" >&2
        return 1
    }
}
