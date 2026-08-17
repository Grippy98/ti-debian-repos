#!/bin/bash

# Extract immutable payloads from the validated TI EdgeAI 11.02 J722S release.
# The archive records the pinned source revisions and checksums used for the
# downstream package set. Firmware and models require TI build tools; the
# imported host binaries remain a temporary baseline until their ordered SDK
# source build is part of this repository's workflow.

edgeai_release_archive="edgeai-debs-j722s-edgeai-debian-11.02.16.00-j722s-20260715.tar.zst"
edgeai_release_url="https://github.com/TexasInstruments-Sandbox/ti-edgeai-armbian-build/releases/download/edgeai-debian-11.02.16.00-j722s-20260715/$edgeai_release_archive"
edgeai_release_sha256="5a5c8686e7fd13ebb45f3f0188f242be6f14cdd8e5d78707e3673c618726d561"

prepare_edgeai_release_payload() {
    local destination=$1
    local cache=$2
    local deb_filename=$3
    local deb_sha256=$4
    local binary_package=$5
    local archive="$cache/$edgeai_release_archive"
    local archive_tmp="${archive}.tmp.$$"
    local member
    local extracted_deb

    if [ ! -f "$archive" ] ||
       ! printf '%s  %s\n' "$edgeai_release_sha256" "$archive" |
         sha256sum --check --status; then
        wget --tries=3 --timeout=30 -O "$archive_tmp" "$edgeai_release_url"
        printf '%s  %s\n' "$edgeai_release_sha256" "$archive_tmp" |
            sha256sum --check --status
        mv "$archive_tmp" "$archive"
    fi

    member=$(tar --zstd -tf "$archive" | grep -F "/$deb_filename" | head -1)
    if [ -z "$member" ]; then
        echo "Missing $deb_filename in $edgeai_release_archive" >&2
        return 1
    fi

    extracted_deb=$(mktemp "$cache/edgeai-release-deb.XXXXXX")
    tar --zstd -xOf "$archive" "$member" >"$extracted_deb"
    printf '%s  %s\n' "$deb_sha256" "$extracted_deb" |
        sha256sum --check --status

    mkdir -p "$destination/payload"
    dpkg-deb -x "$extracted_deb" "$destination/payload"
    rm -f "$extracted_deb"

    # Debian packaging regenerates these files from the current source recipe.
    rm -rf "$destination/payload/usr/share/doc/$binary_package"
}
