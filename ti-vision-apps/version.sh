#!/bin/bash

source "$topdir/scripts/edgeai-release-source.sh"

prepare_source() {
    prepare_edgeai_release_payload "$1" "$2" \
        "libtivision-apps11.2.0_11.02.03-3_arm64.deb" \
        "4d0c1ad88a6f7e42b027b745bd267ef90ad2d4f11ab1cf33f12fedeb64141727" \
        "libtivision-apps11.2.0"
    prepare_edgeai_release_payload "$1" "$2" \
        "libtivision-apps-dev_11.02.03-3_arm64.deb" \
        "51a0ed312b9637b4b22b5bc38fa51a6294bbc873d9898dd5b18daf1e9ae3bb1b" \
        "libtivision-apps-dev"
    prepare_edgeai_release_payload "$1" "$2" \
        "ti-vision-apps-data_11.02.03-3_arm64.deb" \
        "0f6c52582bae032c0d9c41f16fd357f0615792b993838eb62a0eab3760f200be" \
        "ti-vision-apps-data"
}
