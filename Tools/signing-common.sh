#!/bin/bash

# Source this file from the build and one-time local signing setup.
ownclip_local_signing_name='OwnClip Local Code Signing'

ownclip_resolve_signing_identity() {
    local requested="$1"
    local identities matches count
    signing_hash=''
    signing_name=''
    if [[ -z "$requested" || "$requested" == - ]]; then
        printf 'A persistent code signing identity is required; ad-hoc signing is disabled.\n' >&2
        return 1
    fi
    identities=$(/usr/bin/security find-identity -v -p codesigning) || return 1
    matches=$(printf '%s\n' "$identities" | /usr/bin/awk -v requested="$requested" '
        /^[[:space:]]*[0-9]+\) / {
            hash = $2
            name = $0
            sub(/^[^"]*"/, "", name)
            sub(/"[[:space:]]*$/, "", name)
            if (name == requested || toupper(hash) == toupper(requested)) {
                printf "%s\t%s\n", hash, name
            }
        }')
    count=$(printf '%s\n' "$matches" | /usr/bin/awk 'NF { count++ } END { print count+0 }')
    if [[ "$count" != 1 ]]; then
        printf 'Expected one valid signing identity for "%s", found %s.\n' "$requested" "$count" >&2
        printf 'Run ./Tools/setup-signing.sh once, or set OWNCLIP_SIGN_IDENTITY to a valid certificate name or SHA-1 fingerprint.\n' >&2
        return 1
    fi
    IFS=$'\t' read -r signing_hash signing_name <<< "$matches"
}
