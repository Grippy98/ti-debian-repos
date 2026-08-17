#!/bin/bash

source "$topdir/scripts/edgeai-release-source.sh"

prepare_source() {
    prepare_edgeai_release_payload "$1" "$2" \
        "ti-edgeai_11.02.01-9_all.deb" \
        "d964f9cfc9bc9189e27f769f930bb63054ac6c92d91c42a9672b818f1c8b9a7d" \
        "ti-edgeai"

    sed -i \
        's/import ml_dtypes, numpy, onnxruntime, tflite_runtime.interpreter/import edgeai_dl_inferer, ml_dtypes, numpy, onnxruntime, tflite_runtime.interpreter, tidlruntime, tvm/' \
        "$1/payload/usr/sbin/validate-j722s-edgeai"
}
