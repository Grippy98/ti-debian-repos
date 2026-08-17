#!/bin/bash

# Ubuntu Noble 1.24 still advertises invalid endian-suffixed names for three
# 8-bit Bayer formats. Newer GStreamer releases already contain the fix, so
# this source is intentionally built only for Noble.
export source_url="https://ports.ubuntu.com/ubuntu-ports/pool/main/g/gst-plugins-good1.0/gst-plugins-good1.0_1.24.2.orig.tar.xz"
export source_sha256="6e347c72d4b8b2886d890ffe9f6767a9edb02f201588e8c3a572dcd08d9852bd"
export source_strip_components=1

# The upstream suite takes several minutes natively and its fixed 20-second
# element-test timeouts are not viable under Docker/QEMU. The downstream
# change is covered by a focused payload inspection after the package build.
export DEB_BUILD_OPTIONS="${DEB_BUILD_OPTIONS:+$DEB_BUILD_OPTIONS }nocheck"
