#!/bin/bash

source "$topdir/scripts/edgeai-release-source.sh"

prepare_source() {
    prepare_edgeai_release_payload "$1" "$2" \
        "edgeai-gst-plugins_1.0.0-4_arm64.deb" \
        "4a91f36ebe7c9db9693b74f4d4ca887372e74517e5abc5a7d5ae90fb5cd3f100" \
        "edgeai-gst-plugins"
}
