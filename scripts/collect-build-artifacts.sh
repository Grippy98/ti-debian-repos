#!/bin/bash

set -euo pipefail

if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <package> <build-suite> <destination> <target-suites> <expected-architecture>" >&2
    exit 2
fi

package=$1
suite=$2
destination=$3
target_suites=$4
expected_architecture=$5
topdir=$(git rev-parse --show-toplevel)
changelog="$topdir/$package/suite/$suite/debian/changelog"
source_name=$(dpkg-parsechangelog -l"$changelog" --show-field Source)
version=$(dpkg-parsechangelog -l"$changelog" --show-field Version)
builddir="$topdir/build/$suite/$package/$version"

if [ ! -d "$builddir" ]; then
    echo "Build output directory does not exist: $builddir" >&2
    exit 1
fi

mkdir -p "$destination"
shopt -s nullglob
artifacts=(
    "$builddir"/*.deb
    "$builddir"/*.ddeb
    "$builddir"/*.udeb
    "$builddir"/*.changes
    "$builddir"/*.buildinfo
)

deb_count=0
for artifact in "${artifacts[@]}"; do
    case "${artifact##*/}" in
        *-build-deps_*) continue ;;
    esac
    cp -a "$artifact" "$destination/"
    case "$artifact" in
        *.deb|*.ddeb|*.udeb) deb_count=$((deb_count + 1)) ;;
    esac
done

if [ "$deb_count" -eq 0 ]; then
    echo "No Debian binary packages were produced in $builddir" >&2
    exit 1
fi

binary_architectures=()
for artifact in "$destination"/*.deb "$destination"/*.ddeb "$destination"/*.udeb; do
    binary_architectures+=("$(dpkg-deb --field "$artifact" Architecture)")
done
architecture=$(printf '%s\n' "${binary_architectures[@]}" | sort -u | paste -sd, -)
if [ "$architecture" != "$expected_architecture" ]; then
    echo "Built architecture $architecture does not match expected $expected_architecture" >&2
    exit 1
fi
commit=$(git -C "$topdir" rev-parse HEAD)

printf '%s\n' \
    "package=$package" \
    "source=$source_name" \
    "version=$version" \
    "build_suite=$suite" \
    "target_suites=$target_suites" \
    "architecture=$architecture" \
    "commit=$commit" \
    >"$destination/manifest.txt"

(
    cd "$destination"
    checksum_files=()
    for file in *; do
        [ "$file" = SHA256SUMS ] && continue
        checksum_files+=("$file")
    done
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${checksum_files[@]}" >SHA256SUMS
    else
        shasum -a 256 "${checksum_files[@]}" >SHA256SUMS
    fi
)
