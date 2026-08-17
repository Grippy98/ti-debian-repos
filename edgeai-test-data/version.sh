#!/bin/bash

download_checked_source() {
    local url=$1
    local checksum=$2
    local destination=$3
    local temporary

    if [ -f "$destination" ] &&
       printf '%s  %s\n' "$checksum" "$destination" | sha256sum --check --status; then
        return
    fi

    temporary="${destination}.tmp.$$"
    wget --tries=3 --timeout=30 -O "$temporary" "$url"
    printf '%s  %s\n' "$checksum" "$temporary" | sha256sum --check --status
    mv "$temporary" "$destination"
}

prepare_source() {
    local destination=$1
    local cache=$2
    local data_archive="${cache}/edgeai-test-data-11_01_00.tar.gz"
    local oob_archive="${cache}/j722s-oob-demo-assets-11_01_00.tar.gz"

    download_checked_source \
        "https://software-dl.ti.com/jacinto7/esd/edgeai-test-data/11_01_00/edgeai-test-data.tar.gz" \
        "18133afb7ba306dc25489bd4a25da3d6501f02eccae4325aa9793f47c05654db" \
        "$data_archive"
    download_checked_source \
        "https://software-dl.ti.com/jacinto7/esd/edgeai-test-data/11_01_00/j722s-oob-demo-assets.tar.gz" \
        "c842932aa0e0cfd1d03f0772b153f251bdbb842dcdbb53f323291192c6cdd0da" \
        "$oob_archive"

    mkdir -p "$destination/payload/opt" "$destination/payload/usr/share/ti-edgeai"
    tar -xzf "$data_archive" -C "$destination/payload/opt"
    tar -xzf "$oob_archive" -C "$destination/payload/opt"
    mv "$destination/payload/opt/j722s-oob-demo-assets" \
       "$destination/payload/opt/oob-demo-assets"

    for video in "$destination"/payload/opt/oob-demo-assets/*.h264; do
        [ -f "$video" ] || continue
        ln -sf "/opt/oob-demo-assets/${video##*/}" \
            "$destination/payload/opt/edgeai-test-data/videos/${video##*/}"
    done

    (
        cd "$destination/payload"
        find opt -type f -print0 | sort -z | xargs -0 sha256sum
    ) >"$destination/payload/usr/share/ti-edgeai/test-data-files.sha256"
}
