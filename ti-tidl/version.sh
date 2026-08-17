#!/bin/bash

source "$topdir/scripts/edgeai-release-source.sh"

prepare_source() {
    prepare_edgeai_release_payload "$1" "$2" \
        "ti-tidl_1.0.0-1_arm64.deb" \
        "38442e24e3213245c441b9a13a6056091d75bad8d9d68e0080e05e8f3d5c56ef" \
        "ti-tidl"
    prepare_edgeai_release_payload "$1" "$2" \
        "ti-tidl-dev_1.0.0-1_arm64.deb" \
        "226ce5f9a939fe7df0b622d526994a567f7da6781ccce398005bc6480d507e38" \
        "ti-tidl-dev"
}
