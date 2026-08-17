#!/bin/bash

set -euo pipefail

topdir=$(git rev-parse --show-toplevel)
generic_packages="$topdir/scripts/ci-generic-packages.txt"

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

package_supports_suite() {
    local package_root=$1
    local suite=$2
    local supported_suites="$package_root/supported-suites"

    # Existing packages without an explicit allowlist retain the repository's
    # original expectation that every Ubuntu suite is provided.
    if [ ! -f "$supported_suites" ]; then
        return 0
    fi
    grep -Ev '^[[:space:]]*(#|$)' "$supported_suites" | grep -Fqx "$suite"
}

suite_neutral_version() {
    sed -E 's/~(jammy|noble|resolute)[0-9]+$//' <<<"$1"
}

for version_file in "$topdir"/*/version.sh; do
    package_root=${version_file%/version.sh}
    supported_suites="$package_root/supported-suites"
    [ -f "$supported_suites" ] || continue

    while IFS= read -r supported_suite; do
        supported_suite=${supported_suite//[[:space:]]/}
        [ -n "$supported_suite" ] || continue
        [[ "$supported_suite" == \#* ]] && continue
        case "$supported_suite" in
            bookworm|trixie|jammy|noble|resolute) ;;
            *) report_failure "${package_root##*/} declares unsupported suite $supported_suite"; continue ;;
        esac
        if [ ! -f "$package_root/suite/$supported_suite/debian/control" ]; then
            report_failure "${package_root##*/} declares suite $supported_suite but has no packaging for it"
        fi
    done <"$supported_suites"
done

for suite in "$@"; do
    case "$suite" in
        jammy) expected_suffix='~jammy' ;;
        noble) expected_suffix='~noble' ;;
        resolute) expected_suffix='~resolute' ;;
        *) expected_suffix='' ;;
    esac

    controls=()
    for control in "$topdir"/*/suite/"$suite"/debian/control; do
        [ -f "$control" ] || continue
        controls+=("$control")
    done

    if [ "${#controls[@]}" -eq 0 ]; then
        report_failure "no package metadata found for suite $suite"
        continue
    fi

    if [ -n "$expected_suffix" ]; then
        for version_file in "$topdir"/*/version.sh; do
            package_root=${version_file%/version.sh}
            if package_supports_suite "$package_root" "$suite" &&
               [ ! -f "$package_root/suite/$suite/debian/control" ]; then
                report_failure "${package_root##*/} is missing suite $suite"
            fi
        done
    fi

    for control in "${controls[@]}"; do
        debian_dir=${control%/control}
        package_root=${control%/suite/"$suite"/debian/control}
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
                # Compiled Ubuntu variants need distinct suite-qualified
                # versions. Debian suite trees preserve upstream changelog
                # targets and may intentionally reuse versions.
                for other_changelog in "$package_root"/suite/*/debian/changelog; do
                    [ "$other_changelog" = "$changelog" ] && continue
                    other_version=$(dpkg-parsechangelog -l"$other_changelog" --show-field Version)
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

            # A shared binary is safe only when every suite carrying the same
            # base version has byte-identical packaging apart from its changelog.
            version_group=$(suite_neutral_version "$version")
            for other_changelog in "$package_root"/suite/*/debian/changelog; do
                [ "$other_changelog" = "$changelog" ] && continue
                other_version=$(dpkg-parsechangelog -l"$other_changelog" --show-field Version)
                other_version_group=$(suite_neutral_version "$other_version")
                [ "$version_group" = "$other_version_group" ] || continue
                other_debian_dir=${other_changelog%/changelog}
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

        reference_control="$package_root/suite/trixie/debian/control"
        if [ ! -f "$reference_control" ]; then
            reference_control="$package_root/suite/bookworm/debian/control"
        fi
        if [ ! -f "$reference_control" ]; then
            reference_control=$(find "$package_root/suite" \
                -path '*/debian/control' -print | sort | head -1)
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
