#!/bin/bash

source "$topdir/scripts/edgeai-release-source.sh"

prepare_source() {
    prepare_edgeai_release_payload "$1" "$2" \
        "edgeai-dl-inferer_1.0.0-1_arm64.deb" \
        "fbb86f6206613ada1f636d0bec4ac8a146b70a06fdb40af646eab8f676b7f441" \
        "edgeai-dl-inferer"
    prepare_edgeai_release_payload "$1" "$2" \
        "edgeai-dl-inferer-dev_1.0.0-1_arm64.deb" \
        "bac2c8f0018c12266c72e37aadfb0220b6a31f0cc2e36396f04ead7c55d8ed51" \
        "edgeai-dl-inferer-dev"
}
