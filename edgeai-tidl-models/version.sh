#!/bin/bash

source "$topdir/scripts/edgeai-release-source.sh"

prepare_source() {
    prepare_edgeai_release_payload \
        "$1" "$2" \
        "edgeai-tidl-models_11.02.16.00-2_arm64.deb" \
        "556933b1a563db852e6b60176df0c5f64bb6dece3ba22611dec102e0df27a227" \
        "edgeai-tidl-models"
}
