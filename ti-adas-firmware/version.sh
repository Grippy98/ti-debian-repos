#!/bin/bash

source "$topdir/scripts/edgeai-release-source.sh"

prepare_source() {
    prepare_edgeai_release_payload \
        "$1" "$2" \
        "ti-edgeai-firmware-j722s_1.0.0+psdk11.2.1.beagley4gb2-1_arm64.deb" \
        "f850669a7c4b745e8a9b26072a571658f65085ed4416e9a4feac642c95be2f79" \
        "ti-edgeai-firmware-j722s"
}
