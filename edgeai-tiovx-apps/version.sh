#!/bin/bash

source "$topdir/scripts/edgeai-release-source.sh"

prepare_source() {
    prepare_edgeai_release_payload "$1" "$2" \
        "edgeai-tiovx-apps_1.0.0-1_arm64.deb" \
        "74a9d3eaad36b5d93c251ca66868dc5b25c10b2c32019e8bbbd7b599e52456f4" \
        "edgeai-tiovx-apps"
}
