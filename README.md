# Debian-Repos

Debian-Repos is a set of scripts to build TI's Debian and Ubuntu packages with
a single command.

The generation of a Debian package (binary and source) involves many steps, such
as obtaining the tar of the source code, generating template files, modifying
template files and the build system, setting environment variables etc. The
`run.sh` script handles these steps, thus the building of a deb package for TI's
packages is as simple as running `run.sh` with the desired package's name.

This repository is useful to the following audience:
1. Potential package contributors who want to fix bugs or add enhancements to
TI packages
2. Users who want a package with the latest changes to the master branch
3. Anyone who wants to study Debian packaging

## Structure and HowTo Use:

The `run.sh` file is the "main" script that should be run. It takes as argument
the name of the package to be built.

Each TI package has a corresponding directory, named after its source package.
Within this directory exists the `suite/<distro-variant>/debian/` path. All
Debian related files (`control`, `rules`, man pages etc) for the package are
located here.

There also exists a `<package-name>/version.sh` file. This file is sourced by
`run.sh`. It exports a bunch of variables for `run.sh` to use. It also contains
a `run_prep` function, which `run.sh` calls. `run_prep` carries out all
package-specific operations needed to build the deb files.

To build a package, the syntax is:

```sh
./run.sh <package-name>
```

> [!NOTE]
> The default suite is `trixie`. Set `DEB_SUITE` to build another supported
> suite.
>
> ```sh
> DEB_SUITE=bookworm ./run.sh <package-name>
> DEB_SUITE=trixie ./run.sh <package-name>
> DEB_SUITE=jammy ./run.sh <package-name>
> DEB_SUITE=noble ./run.sh <package-name>
> DEB_SUITE=resolute ./run.sh <package-name>
> ```

The repository contains packaging for these Debian and Ubuntu suites:

| Distribution | Suite | Release |
| --- | --- | --- |
| Debian | `bookworm` | Debian 12 |
| Debian | `trixie` (default) | Debian 13 |
| Ubuntu | `jammy` | Ubuntu 22.04 LTS |
| Ubuntu | `noble` | Ubuntu 24.04 LTS |
| Ubuntu | `resolute` | Ubuntu 26.04 LTS |

Not every package supports every suite. Check for
`<package-name>/suite/<suite>/debian/` before building. If a package has a
`supported-suites` file, CI only builds the suites listed there.

This command carries out all necessary steps to build the package. The
package and all related files are then stored in
`build/<suite>/<package-name>`.
Note that certain packages may require root privileges.

For example: to build `ti-linux-kernel`, the command is:

```sh
./run.sh ti-linux-kernel
```

The output is then found in `build/trixie/ti-linux-kernel/`.

Set `BUILD_ROOT` to use a separate output tree, for example when checking a
clean rebuild without disturbing an existing build cache. `SOURCE_CACHE_DIR`
can point that build at a shared download cache.

Packaging metadata can be checked before building with:

```sh
./scripts/validate-packaging.sh bookworm trixie jammy noble resolute
```

## Automated package builds

GitHub Actions builds changed packages on ARM64 for Debian Bookworm and Trixie
and Ubuntu Jammy, Noble, and Resolute. Each changed package is built for every
suite it supports.

Suite-neutral packages listed in `scripts/ci-generic-packages.txt` are built
once per base version and reused for compatible suites. Packages that use an
older version on Bookworm still get a separate Bookworm build. The modern
kernel packages use Trixie metadata in a Jammy build container so the tools in
the header packages remain compatible with the oldest supported glibc. The
packaging validator checks this setup, so full builds do not rebuild every
suite-neutral payload for every suite.

- Pull requests build and retain package artifacts for 14 days.
- Pushes to `master` that change a package create a draft debug prerelease once
  every selected build passes.
- The `Build downstream Debian packages` workflow can also be run manually for
  a comma-separated package list (or `all`) and suite list.

Each release asset is a package/target-suite bundle containing the generated
`.deb`, `.ddeb`, `.udeb`, `.changes`, and `.buildinfo` files, plus a manifest
and SHA-256 checksums. Generic bundles can target multiple suites.

### EdgeAI packages

| Source | Supported suites | Notes |
| --- | --- | --- |
| `ti-rpmsg-char` | All | Built separately for each suite |
| `python3-ml-dtypes` | All | Built separately for each suite |
| `edgeai-test-data` | All | Shared test data |
| `edgeai-tidl-models` | All | AM67A/J722S model payload |
| `ti-adas-firmware` | All | Builds `ti-edgeai-firmware-j722s-4gb` for the BeagleY-AI/J722S 4 GiB memory profile |
| `gst-plugins-good1.0-ti` | Noble | Noble 1.24 still needs the V4L2 Bayer caps fix; newer suites already contain it |
| `ti-tidl-osrt` | Noble, Trixie, Resolute | Native ONNX Runtime and TVM libraries, plus development files |
| `python3-ti-tidl-osrt` | Noble | TI publishes this release's Python modules only for CPython 3.12 |
| `ti-vision-apps` | Noble, Trixie, Resolute | TI OpenVX middleware, headers, and sensor data |
| `ti-tidl` | Noble, Trixie, Resolute | TIDL delegate libraries and headers |
| `edgeai-apps-utils` | Noble, Trixie, Resolute | EdgeAI utility library and headers |
| `edgeai-tiovx-kernels` | Noble, Trixie, Resolute | EdgeAI OpenVX kernels and headers |
| `edgeai-tiovx-modules` | Noble, Trixie, Resolute | EdgeAI OpenVX modules and headers |
| `edgeai-gst-plugins` | Noble, Trixie, Resolute | TI OpenVX and TIDL GStreamer plugins |
| `edgeai-dl-inferer` | Noble | Uses TI's CPython 3.12 OSRT modules |
| `edgeai-tiovx-apps` | Noble | Current build links Noble's FFmpeg 6 ABI |
| `edgeai-gst-apps` | Noble | Current build links Noble's OpenCV 4.6 ABI and Python 3.12 OSRT |
| `ti-edgeai` | Noble | Installs the complete matching EdgeAI stack |

The imported PSDK host binaries need glibc 2.38 and GLIBCXX 3.4.32, so they
cannot run on Bookworm or Jammy. Supporting those suites requires rebuilding
TI Vision Apps, TIDL, ONNX Runtime, TVM, and their dependants against the older
userspace. Trixie and Resolute can use the native runtime, but TI does not
publish compatible Python bindings for their Python versions.

### Deferred `linux-libc-dev` review

The standard and RT kernel builds currently emit TI's `linux-libc-dev`
alongside the versioned image and header packages. Compared with upstream
Linux 6.12.17, the TI UAPI differs in four headers: RGB-IR Bayer media formats,
IR and background-detection V4L2 controls, and a remoteproc DMA-BUF attach
ioctl. None of the packages in this repository currently requires those
downstream headers; normal builds use each distribution's `linux-libc-dev`.

The TI package version also sorts newer than the distribution version, which
could block normal header updates. The `linux-libc-dev` branch is kept for a
separate review. For now, avoid installing TI's `linux-libc-dev` on a general
Debian or Ubuntu system unless the downstream UAPI is needed.
