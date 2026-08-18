#!/bin/bash

set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <package-root> <suite> <destination-debian-dir>" >&2
    exit 2
fi

package_root=$1
suite=$2
destination=$3
common_dir="$package_root/common/debian"
suite_dir="$package_root/suite/$suite/debian"

if [ ! -d "$suite_dir" ]; then
    echo "${package_root##*/} does not provide packaging for suite $suite" >&2
    exit 2
fi

mkdir -p "$destination"

if [ -d "$common_dir" ]; then
    cp -a "$common_dir/." "$destination/"
fi
cp -a "$suite_dir/." "$destination/"

for required_file in changelog control rules; do
    if [ ! -f "$destination/$required_file" ]; then
        echo "${package_root##*/}/$suite is missing debian/$required_file after assembly" >&2
        exit 2
    fi
done
