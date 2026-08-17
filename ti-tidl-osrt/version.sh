#!/bin/bash

prepare_source() {
    local destination=$1
    local cache=$2
    local base_url="https://software-dl.ti.com/jacinto7/esd/tidl-tools/11_02_16_00/OSRT_TOOLS/ARM_LINUX/ARAGO"
    local stage="$destination/staging"

    fetch_artifact() {
        local filename=$1
        local checksum=$2
        local artifact="$cache/$filename"
        local artifact_tmp="${artifact}.tmp.$$"

        if [ ! -f "$artifact" ] ||
           ! printf '%s  %s\n' "$checksum" "$artifact" |
             sha256sum --check --status; then
            wget --tries=3 --timeout=30 -O "$artifact_tmp" \
                "$base_url/$filename"
            printf '%s  %s\n' "$checksum" "$artifact_tmp" |
                sha256sum --check --status
            mv "$artifact_tmp" "$artifact"
        fi
    }

    fetch_artifact \
        tflite_runtime-2.12.0-cp312-cp312-linux_aarch64.whl \
        1d0d2713956476b20eb765eeb71ad507d69c391e73a05b356dd5990e2b36ad3f
    fetch_artifact \
        onnxruntime_tidl-1.23.0-cp312-cp312-linux_aarch64.whl \
        5b5b0ef852cf059bb3ee03996bc782900155f5b19eda63e1fce84fa13ac1648a
    fetch_artifact \
        tvm-0.18.0-cp312-cp312-linux_aarch64.whl \
        98e2d8f2c4ebb14eccc6bd1dfb1df6f0a872141fe7fd83e6fe41175f710648bd
    fetch_artifact \
        tidlruntime-0.1.0-cp312-cp312-linux_aarch64.whl \
        384d825a362db72411c10eccacfbbef5d4b487c159982a17e2788bb724c5a51e
    fetch_artifact \
        tflite_2.12_aragoj7.tar.gz \
        81b5c8d85725dace8baa0e9dbdceb1f79916d427797299566fb0b74ed8293a80
    fetch_artifact \
        onnx_1.23.0_aragoj7.tar.gz \
        27a1a39fb44b22a149f1fc13619f33d07cab7c6c07012789ede3f935c971e7f3

    mkdir -p "$stage/python" "$stage/lib" "$stage/include" "$stage/tmp"
    for wheel in \
        tflite_runtime-2.12.0-cp312-cp312-linux_aarch64.whl \
        onnxruntime_tidl-1.23.0-cp312-cp312-linux_aarch64.whl \
        tvm-0.18.0-cp312-cp312-linux_aarch64.whl \
        tidlruntime-0.1.0-cp312-cp312-linux_aarch64.whl; do
        unzip -q "$cache/$wheel" -d "$stage/python"
    done

    mkdir -p "$stage/tmp/tflite" "$stage/tmp/onnx"
    tar -xzf "$cache/tflite_2.12_aragoj7.tar.gz" -C "$stage/tmp/tflite"
    tar -xzf "$cache/onnx_1.23.0_aragoj7.tar.gz" -C "$stage/tmp/onnx"
    local tflite_top
    local onnx_top
    tflite_top=$(find "$stage/tmp/tflite" -mindepth 1 -maxdepth 1 -type d | head -1)
    onnx_top=$(find "$stage/tmp/onnx" -mindepth 1 -maxdepth 1 -type d | head -1)

    cp -a "$tflite_top/tensorflow" "$stage/include/"
    cp -a "$tflite_top/tflite_2.12" "$stage/lib/"
    cp -a "$tflite_top/libtensorflow-lite.a" "$stage/lib/"

    cp -a "$onnx_top/libonnxruntime.so.1.23.0" "$stage/lib/"
    ln -s libonnxruntime.so.1.23.0 "$stage/lib/libonnxruntime.so"
    rm -rf "$onnx_top/onnxruntime/csharp"
    cp -a "$onnx_top/onnxruntime" "$stage/include/"

    if [ -f "$stage/python/tidlruntime/lib/libtidlruntime.a" ]; then
        cp -a "$stage/python/tidlruntime/lib/libtidlruntime.a" "$stage/lib/"
    fi
    if [ -d "$stage/python/tidlruntime/include" ]; then
        cp -a "$stage/python/tidlruntime/include" "$stage/include/tidlruntime"
    fi
    if [ -f "$stage/python/tvm/libtvm.so" ]; then
        ln -s python3/dist-packages/tvm/libtvm.so "$stage/lib/libtvm.so"
        ln -s python3/dist-packages/tvm/libtvm_runtime.so \
            "$stage/lib/libtvm_runtime.so"
    fi

    rm -rf "$stage/tmp"
    find "$stage" -type d -name __pycache__ -prune -exec rm -rf {} +
}
