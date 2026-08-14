#!/bin/bash

set -euo pipefail

topdir=$(git rev-parse --show-toplevel)

if [ "$#" -eq 0 ]; then
    set -- jammy noble resolute
fi

for command in dpkg-checkbuilddeps dpkg-parsechangelog make; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Missing required command: $command" >&2
        exit 1
    fi
done

failures=0

report_failure() {
    echo "ERROR: $*" >&2
    failures=$((failures + 1))
}

for suite in "$@"; do
    case "$suite" in
        jammy) expected_suffix='~jammy' ;;
        noble) expected_suffix='~noble' ;;
        resolute) expected_suffix='~resolute' ;;
        *) expected_suffix='' ;;
    esac

    controls=()
    while IFS= read -r control; do
        controls+=("$control")
    done < <(find "$topdir" -path "*/suite/$suite/debian/control" -print | sort)

    if [ "${#controls[@]}" -eq 0 ]; then
        report_failure "no package metadata found for suite $suite"
        continue
    fi

    if [ -n "$expected_suffix" ]; then
        for version_file in "$topdir"/*/version.sh; do
            package_root=${version_file%/version.sh}
            if [ ! -f "$package_root/suite/$suite/debian/control" ]; then
                report_failure "${package_root##*/} is missing suite $suite"
            fi
        done
    fi

    for control in "${controls[@]}"; do
        debian_dir=${control%/control}
        package_root=${control%/suite/$suite/debian/control}
        package=${package_root##*/}
        changelog="$debian_dir/changelog"
        rules="$debian_dir/rules"

        if ! changelog_error=$(dpkg-parsechangelog --all -l"$changelog" 2>&1 >/dev/null); then
            report_failure "$package/$suite changelog could not be parsed: $changelog_error"
            continue
        fi
        if [ -n "$changelog_error" ]; then
            report_failure "$package/$suite has changelog warnings: $changelog_error"
            continue
        fi

        distribution=$(dpkg-parsechangelog -l"$changelog" --show-field Distribution)
        version=$(dpkg-parsechangelog -l"$changelog" --show-field Version)
        if [ "$distribution" != "$suite" ]; then
            report_failure "$package/$suite changelog targets $distribution"
        fi
        if [ -n "$expected_suffix" ] && [[ "$version" != *"$expected_suffix"* ]]; then
            report_failure "$package/$suite version $version lacks $expected_suffix"
        fi

        for other_changelog in "$package_root"/suite/*/debian/changelog; do
            [ "$other_changelog" = "$changelog" ] && continue
            other_version=$(dpkg-parsechangelog -l"$other_changelog" --show-field Version)
            if [ "$version" = "$other_version" ]; then
                report_failure "$package reuses version $version in multiple suites"
            fi
        done

        control_error=$(dpkg-checkbuilddeps "$control" 2>&1) || true
        control_error_lower=${control_error,,}
        if [ -n "$control_error" ] && [[ "$control_error_lower" != *"unmet build dependencies:"* ]]; then
            report_failure "$package/$suite has invalid control metadata: $control_error"
        fi

        if [ ! -x "$rules" ]; then
            report_failure "$package/$suite debian/rules is not executable"
        fi

        reference_control="$package_root/suite/trixie/debian/control"
        if [ ! -f "$reference_control" ]; then
            reference_control="$package_root/suite/bookworm/debian/control"
        fi
        reference_maintainer=$(sed -n 's/^Maintainer: //p' "$reference_control" | head -1)
        suite_maintainer=$(sed -n 's/^Maintainer: //p' "$control" | head -1)
        if [ "$suite_maintainer" != "$reference_maintainer" ]; then
            report_failure "$package/$suite changes Maintainer from '$reference_maintainer' to '$suite_maintainer'"
        fi
    done

    mesa_dir="$topdir/mesa/suite/$suite"
    if [ -f "$mesa_dir/debian/control.in" ]; then
        tempdir=$(mktemp -d)
        cp -a "$mesa_dir/debian" "$tempdir/debian"
        (cd "$tempdir" && make -s -f debian/rules regen_control)
        if ! cmp -s "$mesa_dir/debian/control" "$tempdir/debian/control"; then
            report_failure "mesa/$suite debian/control is not regenerated from control.in"
        fi
        rm -rf "$tempdir"
    fi

    echo "Validated ${#controls[@]} packages for $suite"
done

if [ "$failures" -ne 0 ]; then
    echo "$failures validation error(s)" >&2
    exit 1
fi
