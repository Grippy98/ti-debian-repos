#!/bin/bash

source "$topdir/scripts/edgeai-release-source.sh"

prepare_source() {
    prepare_edgeai_release_payload "$1" "$2" \
        "edgeai-apps-utils_1.0.0-1_arm64.deb" \
        "17cb494d424cef812a5ea46e0f27af9e842d3f6e7243746610df794b552289ca" \
        "edgeai-apps-utils"
    prepare_edgeai_release_payload "$1" "$2" \
        "edgeai-apps-utils-dev_1.0.0-1_arm64.deb" \
        "e71b02e3bb909f5bc7d63593d69cfd1f71d1fc8e59bcd5b7390dde833044e24a" \
        "edgeai-apps-utils-dev"
}
