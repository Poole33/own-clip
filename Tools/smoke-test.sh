#!/bin/bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/OwnClip-tests.XXXXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/module-cache"
source "$project_dir/Tools/source-files.sh"
ownclip_collect_sources "$project_dir/Sources"
test_sources=()
for source_file in "${ownclip_sources[@]}"; do
    if [[ "$source_file" != "$project_dir/Sources/main.swift" ]]; then
        test_sources+=("$source_file")
    fi
done
cd -- "$work_dir"
/usr/bin/xcrun swiftc -swift-version 5 -lsqlite3 \
    "${test_sources[@]}" "$project_dir"/Tests/*.swift -o "$work_dir/SmokeTests"
"$work_dir/SmokeTests"
