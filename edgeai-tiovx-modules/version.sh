#!/bin/bash

source "$topdir/scripts/edgeai-release-source.sh"

prepare_source() {
    prepare_edgeai_release_payload "$1" "$2" \
        "edgeai-tiovx-modules_1.0.0-1_arm64.deb" \
        "3bcf51c1cde9e000202fadc32a1987086ee6437220a2eb497b16aa1aa9e8a5a1" \
        "edgeai-tiovx-modules"
    prepare_edgeai_release_payload "$1" "$2" \
        "edgeai-tiovx-modules-dev_1.0.0-1_arm64.deb" \
        "99ceebf5381973c8a5a1f90f747af554dcadc8854166f07896f1fbd99e3a80cc" \
        "edgeai-tiovx-modules-dev"
}
