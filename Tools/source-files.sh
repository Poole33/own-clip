#!/bin/bash

# Bash 3.2 compatible; preserve paths with spaces using NUL-delimited discovery.
# Source this helper, then call ownclip_collect_sources with the Sources directory.
ownclip_collect_sources() {
    ownclip_sources=()
    while IFS= read -r -d '' source_file; do
        ownclip_sources+=("$source_file")
    done < <(/usr/bin/find "$1" -type f -name '*.swift' -print0)
}
