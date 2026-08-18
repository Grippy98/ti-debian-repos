#!/bin/bash

set -euo pipefail

topdir=$(git rev-parse --show-toplevel)
generic_packages="$topdir/scripts/ci-generic-packages.txt"
metadata_root=$(mktemp -d)
trap 'rm -rf "$metadata_root"' EXIT

if [ "$#" -eq 0 ]; then
    set -- bookworm trixie jammy noble resolute
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

is_generic_package() {
    grep -Ev '^[[:space:]]*(#|$)' "$generic_packages" | grep -Fqx "$1"
}

suite_neutral_version() {
    sed -E 's/~(jammy|noble|resolute)[0-9]+$//' <<<"$1"
}

assembled_debian_dir() {
    local package_root=$1
    local suite=$2
    local package=${package_root##*/}
    local destination="$metadata_root/$package/$suite/debian"

    if [ ! -d "$destination" ]; then
        "$topdir/scripts/assemble-debian.sh" \
            "$package_root" "$suite" "$destination"
    fi
    printf '%s\n' "$destination"
}

for version_file in "$topdir"/*/version.sh; do
    package_root=${version_file%/version.sh}
    common_dir="$package_root/common/debian"
    [ -d "$common_dir" ] || continue

    for suite_dir in "$package_root"/suite/*/debian; do
        [ -d "$suite_dir" ] || continue
        while IFS= read -r suite_file; do
            relative_path=${suite_file#"$suite_dir"/}
            common_file="$common_dir/$relative_path"
            if [ -f "$common_file" ] && cmp -s "$common_file" "$suite_file"; then
                if { [ -x "$common_file" ] && [ -x "$suite_file" ]; } ||
                   { [ ! -x "$common_file" ] && [ ! -x "$suite_file" ]; }; then
                    report_failure "${package_root##*/}/${suite_dir#"$package_root"/} duplicates common/debian/$relative_path"
                fi
            fi
        done < <(find "$suite_dir" -type f -print)
    done
done

for suite in "$@"; do
    case "$suite" in
        jammy) expected_suffix='~jammy' ;;
        noble) expected_suffix='~noble' ;;
        resolute) expected_suffix='~resolute' ;;
        *) expected_suffix='' ;;
    esac

    if [ -n "$expected_suffix" ]; then
        for version_file in "$topdir"/*/version.sh; do
            package_root=${version_file%/version.sh}
            if [ ! -d "$package_root/suite/$suite/debian" ]; then
                report_failure "${package_root##*/} is missing suite $suite"
            fi
        done
    fi

    package_count=0
    for version_file in "$topdir"/*/version.sh; do
        package_root=${version_file%/version.sh}
        [ -d "$package_root/suite/$suite/debian" ] || continue

        package=${package_root##*/}
        debian_dir=$(assembled_debian_dir "$package_root" "$suite")
        control="$debian_dir/control"
        changelog="$debian_dir/changelog"
        rules="$debian_dir/rules"
        package_count=$((package_count + 1))

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
        generic=0
        if is_generic_package "$package"; then
            generic=1
        fi

        if [ -n "$expected_suffix" ]; then
            if [ "$distribution" != "$suite" ]; then
                report_failure "$package/$suite changelog targets $distribution"
            fi
            if [[ "$version" != *"$expected_suffix"* ]]; then
                report_failure "$package/$suite version $version lacks $expected_suffix"
            fi

            if [ "$generic" -eq 0 ]; then
                for other_suite_dir in "$package_root"/suite/*/debian; do
                    [ "$other_suite_dir" = "$package_root/suite/$suite/debian" ] && continue
                    other_suite=$(basename "$(dirname "$other_suite_dir")")
                    other_debian_dir=$(assembled_debian_dir "$package_root" "$other_suite")
                    other_version=$(dpkg-parsechangelog \
                        -l"$other_debian_dir/changelog" --show-field Version)
                    if [ "$version" = "$other_version" ]; then
                        report_failure "$package reuses version $version in multiple suites"
                    fi
                done
            fi
        fi

        if [ "$generic" -eq 1 ]; then
            architectures=$(awk '$1 == "Architecture:" {print $2}' "$control" | sort -u | paste -sd, -)
            case "$architectures" in
                all|arm64) ;;
                *) report_failure "$package/$suite is marked generic but has unsafe architectures: $architectures" ;;
            esac

            version_group=$(suite_neutral_version "$version")
            for other_suite_dir in "$package_root"/suite/*/debian; do
                [ "$other_suite_dir" = "$package_root/suite/$suite/debian" ] && continue
                other_suite=$(basename "$(dirname "$other_suite_dir")")
                other_debian_dir=$(assembled_debian_dir "$package_root" "$other_suite")
                other_version=$(dpkg-parsechangelog \
                    -l"$other_debian_dir/changelog" --show-field Version)
                other_version_group=$(suite_neutral_version "$other_version")
                [ "$version_group" = "$other_version_group" ] || continue
                if ! diff -qr --exclude=changelog "$debian_dir" "$other_debian_dir" >/dev/null; then
                    report_failure "$package base version $version_group has suite-specific packaging"
                fi
            done
        fi

        control_error=$(dpkg-checkbuilddeps "$control" 2>&1) || true
        control_error_lower=${control_error,,}
        if [ -n "$control_error" ] && [[ "$control_error_lower" != *"unmet build dependencies:"* ]]; then
            report_failure "$package/$suite has invalid control metadata: $control_error"
        fi

        if [ ! -x "$rules" ]; then
            report_failure "$package/$suite debian/rules is not executable"
        fi

        if [ -d "$package_root/suite/trixie/debian" ]; then
            reference_debian_dir=$(assembled_debian_dir "$package_root" trixie)
        elif [ -d "$package_root/suite/bookworm/debian" ]; then
            reference_debian_dir=$(assembled_debian_dir "$package_root" bookworm)
        else
            reference_suite_dir=$(find "$package_root/suite" -mindepth 2 -maxdepth 2 \
                -type d -name debian -print | sort | head -1)
            reference_suite=$(basename "$(dirname "$reference_suite_dir")")
            reference_debian_dir=$(assembled_debian_dir "$package_root" "$reference_suite")
        fi
        reference_maintainer=$(sed -n 's/^Maintainer: //p' \
            "$reference_debian_dir/control" | head -1)
        suite_maintainer=$(sed -n 's/^Maintainer: //p' "$control" | head -1)
        if [ "$suite_maintainer" != "$reference_maintainer" ]; then
            report_failure "$package/$suite changes Maintainer from '$reference_maintainer' to '$suite_maintainer'"
        fi

        if [ "$package" = mesa ] && [ -f "$debian_dir/control.in" ]; then
            mesa_tempdir=$(mktemp -d)
            cp -a "$debian_dir" "$mesa_tempdir/debian"
            (cd "$mesa_tempdir" && make -s -f debian/rules regen_control)
            if ! cmp -s "$debian_dir/control" "$mesa_tempdir/debian/control"; then
                report_failure "mesa/$suite debian/control is not regenerated from control.in"
            fi
            rm -rf "$mesa_tempdir"
        fi
    done

    if [ "$package_count" -eq 0 ]; then
        report_failure "no package metadata found for suite $suite"
    fi
    echo "Validated $package_count packages for $suite"
done

if [ "$failures" -ne 0 ]; then
    echo "$failures validation error(s)" >&2
    exit 1
fi
