#!/bin/bash

source "$topdir/scripts/edgeai-release-source.sh"

prepare_source() {
    prepare_edgeai_release_payload "$1" "$2" \
        "edgeai-gst-apps_1.0.0-1_arm64.deb" \
        "ae5d9c8b69efcf6ba5666f86842454c7d1fa0882f8f488f115242fb3981c6c98" \
        "edgeai-gst-apps"
}
