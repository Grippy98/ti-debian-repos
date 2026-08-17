#!/bin/bash

source "$topdir/scripts/edgeai-release-source.sh"

prepare_source() {
    prepare_edgeai_release_payload "$1" "$2" \
        "edgeai-tiovx-kernels_1.0.0-1_arm64.deb" \
        "46361d4cee40938d7ed851d9b81ca3a72cd08d2e17e03b3e1f39c5be83b91abd" \
        "edgeai-tiovx-kernels"
    prepare_edgeai_release_payload "$1" "$2" \
        "edgeai-tiovx-kernels-dev_1.0.0-1_arm64.deb" \
        "be2544abf6fa4af486adf274c517e057c3d9fb7e8f864a28f5b915338990328f" \
        "edgeai-tiovx-kernels-dev"
}
