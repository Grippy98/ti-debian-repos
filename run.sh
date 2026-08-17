#!/bin/bash

set -e

retry_git_fetch() {
    local repository=$1
    shift
    local delay

    for delay in 0 5 15; do
        if [ "$delay" -ne 0 ]; then
            echo "Git fetch failed; retrying in $delay seconds" >&2
            sleep "$delay"
        fi
        if git -C "$repository" fetch "$@"; then
            return 0
        fi
    done
    return 1
}

if [ "$#" -eq 0 ]; then
    echo "run.sh: missing operands"
    echo "Requires source package name as argument"
    exit 1
fi

DEB_SUITE="${DEB_SUITE:-trixie}"

topdir=$(git rev-parse --show-toplevel)
projdir="${topdir}/$1"
buildroot="${BUILD_ROOT:-${topdir}/build}"
sourcedir="${SOURCE_CACHE_DIR:-${topdir}/build/sources}"
builddir="${buildroot}/${DEB_SUITE}/$1"
debcontroldir="${projdir}/suite/${DEB_SUITE}"

if [ ! -d ${projdir} ]; then
    echo "This project does not exist."
    echo "Exiting."
    exit 1
fi

source ${projdir}/version.sh

mkdir -p ${builddir}

package_name=$(cd ${debcontroldir} && dpkg-parsechangelog --show-field Source)
deb_version=$(cd ${debcontroldir} && dpkg-parsechangelog --show-field Version)
package_version=$(echo $deb_version | sed 's/\(.*\)-.*/\1/')
last_tested_commit=$(echo $package_version | sed 's/.*+//')
source_revision=${git_revision:-$last_tested_commit}
package_full="${package_name}-${package_version}"
package_full_ll="${package_name}_${package_version}"
orig_tar="${builddir}/${package_full_ll}.orig.tar.gz"
echo "Building " $package_name " version " $deb_version

# Discard an interrupted source archive rather than treating it as a valid
# cache entry on the next build.
if [ -f "$orig_tar" ] && ! tar -tzf "$orig_tar" >/dev/null 2>&1; then
    rm -f "$orig_tar"
fi

# Generate original source tarball if none found
if [ ! -f "$orig_tar" ]; then
    mkdir -p "${sourcedir}"
    if declare -F prepare_source >/dev/null; then
        source_unpack=$(mktemp -d "${sourcedir}/${package_name}.XXXXXX")
        mkdir -p "${source_unpack}/${package_full}"
        prepare_source "${source_unpack}/${package_full}" "$sourcedir"
        orig_tar_tmp="${orig_tar}.tmp.$$"
        tar -czf "$orig_tar_tmp" -C "$source_unpack" "$package_full"
        mv "$orig_tar_tmp" "$orig_tar"
        rm -r "$source_unpack"
    elif [ -n "${source_url:-}" ]; then
        source_archive="${sourcedir}/${package_name}-${package_version}.source.tar"
        if [ ! -f "$source_archive" ] ||
           ! printf '%s  %s\n' "$source_sha256" "$source_archive" | sha256sum --check --status; then
            source_archive_tmp="${source_archive}.tmp.$$"
            wget --tries=3 --timeout=30 -O "$source_archive_tmp" "$source_url"
            printf '%s  %s\n' "$source_sha256" "$source_archive_tmp" | sha256sum --check --status
            mv "$source_archive_tmp" "$source_archive"
        fi

        source_unpack=$(mktemp -d "${sourcedir}/${package_name}.XXXXXX")
        mkdir -p "${source_unpack}/${package_full}"
        tar -xf "$source_archive" \
          --strip-components="${source_strip_components:-1}" \
          -C "${source_unpack}/${package_full}"
        orig_tar_tmp="${orig_tar}.tmp.$$"
        tar -czf "$orig_tar_tmp" -C "$source_unpack" "$package_full"
        mv "$orig_tar_tmp" "$orig_tar"
        rm -r "$source_unpack"
    else
        source_repo="${sourcedir}/${package_name}"
        if [ ! -d "${source_repo}/.git" ]; then
            mkdir -p "${source_repo}"
            git -C "${source_repo}" init
            git -C "${source_repo}" remote add origin "${git_repo}"
        fi
        checkout_revision="${source_revision}"
        if ! git -C "${source_repo}" cat-file -e "${source_revision}^{commit}" 2>/dev/null; then
            # Fetch only the revision used by the package. Some servers reject a
            # direct fetch of an abbreviated commit, so retain a full-fetch fallback.
            if retry_git_fetch "${source_repo}" --depth 1 origin "${source_revision}"; then
                checkout_revision=FETCH_HEAD
            else
                retry_git_fetch "${source_repo}" origin
            fi
        fi
        git -C "${source_repo}" checkout --detach "${checkout_revision}"
        git -C "${source_repo}" submodule update --init --recursive
        orig_tar_tmp="${orig_tar}.tmp.$$"
        tar -czf "$orig_tar_tmp" \
          --exclude-vcs \
          --absolute-names "${source_repo}" \
          --transform "s,${source_repo},${package_full},"
        mv "$orig_tar_tmp" "$orig_tar"
    fi
fi

# Generate source package if none found
if [ ! -f "${builddir}/${package_name}_${deb_version}.dsc" ]; then
    # Extract original source tarball
    tar -xzmf "${builddir}/${package_full_ll}.orig.tar.gz" -C "${builddir}"

    # Deploy our Debian control files
    cp -rv "${debcontroldir}/debian" "${builddir}/${package_full}/"

    # Build source package
    (cd "${builddir}/${package_full}" && dpkg-source -b .)

    # Cleanup intermediate source directory
    rm -r "${builddir}/${package_full}"
fi

# Generate binary package for this arch if not found
build_arch=$(dpkg --print-architecture)
if [ ! -f "${builddir}/${package_name}_${deb_version}_${build_arch}.buildinfo" ]; then
    if declare -F run_prep >/dev/null; then
        run_prep
    fi

    # Extract source package
    if [ ! -d "${builddir}/${package_name}_${deb_version}" ]; then
        dpkg-source -x "${builddir}/${package_name}_${deb_version}.dsc" "${builddir}/${package_name}_${deb_version}"
    fi

    # Install build dependencies. Run mk-build-deps outside the unpacked source
    # tree so older releases do not leave generated build-dependency artifacts
    # that dpkg-source mistakes for upstream changes.
    (cd "${builddir}" && mk-build-deps -ir -t "apt-get -o Debug::pkgProblemResolver=yes -y --no-install-recommends" \
      "${package_name}_${deb_version}/debian/control")

    # Build debian package.
    # HACK: There is an issue with building source package for Linux Kernel. So only build binary packages for Linux.
    build_status=0
    if [[ "${package_name}" == "ti-linux-kernel"* ]]; then
        (cd "${builddir}/${package_name}_${deb_version}" && debuild --no-lintian --no-sign -b) || build_status=$?
    else
        (cd "${builddir}/${package_name}_${deb_version}" && debuild --no-lintian --no-sign -sa) || build_status=$?
    fi

    # Cleanup intermediate build directory
    rm -r "${builddir}/${package_name}_${deb_version}"

    if [ "$build_status" -ne 0 ]; then
        exit "$build_status"
    fi
fi
