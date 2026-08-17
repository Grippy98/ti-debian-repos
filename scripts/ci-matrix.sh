#!/bin/bash

set -euo pipefail

topdir=$(git rev-parse --show-toplevel)
base=${1:-}
head=${2:-HEAD}
requested_packages=${CI_PACKAGES:-}
requested_suites=${CI_SUITES:-bookworm,trixie,jammy,noble,resolute}

package_list=$(mktemp)
suite_list=$(mktemp)
matrix_rows=$(mktemp)
package_rows=$(mktemp)
changed_files=$(mktemp)
generic_packages="$topdir/scripts/ci-generic-packages.txt"
trap 'rm -f "$package_list" "$suite_list" "$matrix_rows" "$package_rows" "$changed_files"' EXIT

list_all_packages() {
    for version_file in "$topdir"/*/version.sh; do
        basename "${version_file%/version.sh}"
    done
}

suite_image() {
    case "$1" in
        bookworm|trixie) printf 'debian:%s\n' "$1" ;;
        jammy|noble|resolute) printf 'ubuntu:%s\n' "$1" ;;
        *)
            echo "Unsupported CI suite: $1" >&2
            return 2
            ;;
    esac
}

changelog_version() {
    sed -n '1{s/^[^(]*(\([^)]*\)).*/\1/p;q;}' "$1"
}

suite_neutral_version() {
    sed -E 's/~(jammy|noble|resolute)[0-9]+$//' <<<"$1"
}

package_architecture() {
    awk '$1 == "Architecture:" {print $2}' "$1" | sort -u | paste -sd, -
}

is_generic_package() {
    grep -Ev '^[[:space:]]*(#|$)' "$generic_packages" | grep -Fqx "$1"
}

if [ -n "$requested_packages" ]; then
    printf '%s\n' "$requested_packages" | tr ',' '\n' | while IFS= read -r package; do
        package=${package//[[:space:]]/}
        [ -n "$package" ] && printf '%s\n' "$package"
    done >"$package_list"

    if grep -qx all "$package_list"; then
        list_all_packages >"$package_list"
    fi
else
    if [ -z "$base" ]; then
        echo "A base revision is required when CI_PACKAGES is not set" >&2
        exit 2
    fi

    git diff --name-only "$base" "$head" >"$changed_files"
    rebuild_all=0
    while IFS= read -r path; do
        case "$path" in
            run.sh|scripts/validate-packaging.sh|scripts/ci-matrix.sh|scripts/ci-generic-packages.txt|scripts/collect-build-artifacts.sh|.github/workflows/package-build.yml)
                rebuild_all=1
                ;;
        esac

        package=${path%%/*}
        if [ -f "$topdir/$package/version.sh" ]; then
            printf '%s\n' "$package" >>"$package_list"
        fi
    done <"$changed_files"

    if [ "$rebuild_all" -eq 1 ]; then
        list_all_packages >"$package_list"
    fi
fi

sort -u -o "$package_list" "$package_list"
printf '%s\n' "$requested_suites" | tr ',' '\n' | while IFS= read -r suite; do
    suite=${suite//[[:space:]]/}
    [ -n "$suite" ] && printf '%s\n' "$suite"
done | sort -u >"$suite_list"

while IFS= read -r suite; do
    [ -n "$suite" ] || continue
    suite_image "$suite" >/dev/null
done <"$suite_list"

while IFS= read -r package; do
    [ -n "$package" ] || continue
    if [ ! -f "$topdir/$package/version.sh" ]; then
        echo "Unknown package: $package" >&2
        exit 2
    fi

    generic=0
    if is_generic_package "$package"; then
        generic=1
    fi

    : >"$package_rows"
    while IFS= read -r suite; do
        [ -n "$suite" ] || continue
        if [ -d "$topdir/$package/suite/$suite/debian" ]; then
            version=$(changelog_version "$topdir/$package/suite/$suite/debian/changelog")
            version_group=$version
            if [ "$generic" -eq 1 ]; then
                version_group=$(suite_neutral_version "$version")
            fi
            image=$(suite_image "$suite")
            printf '%s\t%s\t%s\t%s\n' \
                "$version" "$version_group" "$suite" "$image" >>"$package_rows"
        fi
    done <"$suite_list"

    if [ "$generic" -eq 1 ]; then
        cut -f2 "$package_rows" | sort -u | while IFS= read -r version_group; do
            [ -n "$version_group" ] || continue
            targets=$(awk -F '\t' -v version_group="$version_group" \
                '$2 == version_group {print $3}' "$package_rows" | paste -sd, -)
            canonical_suite=
            for candidate in trixie bookworm; do
                candidate_changelog="$topdir/$package/suite/$candidate/debian/changelog"
                if [ -f "$candidate_changelog" ] &&
                   [ "$(suite_neutral_version "$(changelog_version "$candidate_changelog")")" = "$version_group" ]; then
                    canonical_suite=$candidate
                    break
                fi
            done
            if [ -z "$canonical_suite" ]; then
                canonical_suite=$(awk -F '\t' -v version_group="$version_group" \
                    '$2 == version_group {print $3; exit}' "$package_rows")
            fi
            version=$(changelog_version "$topdir/$package/suite/$canonical_suite/debian/changelog")
            image=$(suite_image "$canonical_suite")
            architecture=$(package_architecture "$topdir/$package/suite/$canonical_suite/debian/control")
            artifact_targets=${targets//,/-}
            artifact_architecture=${architecture//,/-}
            artifact="deb-$package-$artifact_targets-$artifact_architecture"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$package" "$canonical_suite" "$image" "$targets" "$architecture" "$artifact" "$version" \
                >>"$matrix_rows"
        done
    else
        while IFS=$'\t' read -r version version_group suite image; do
            [ -n "$suite" ] || continue
            artifact="deb-$package-$suite-arm64"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$package" "$suite" "$image" "$suite" arm64 "$artifact" "$version" \
                >>"$matrix_rows"
        done <"$package_rows"
    fi
done <"$package_list"

jq -Rsc '
    split("\n")
    | map(select(length > 0) | split("\t"))
    | {include: map({
        package: .[0],
        suite: .[1],
        image: .[2],
        targets: .[3],
        architecture: .[4],
        artifact: .[5],
        version: .[6]
    })}
' <"$matrix_rows"
