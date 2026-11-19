#!/bin/bash
set -euo pipefail
umask 077

tools_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$tools_dir/signing-common.sh"

case "${1:-}" in
    ''|--check) ;;
    *) printf 'Usage: %s [--check]\n' "$0" >&2; exit 1 ;;
esac
if [[ $# -gt 1 ]]; then
    printf 'Usage: %s [--check]\n' "$0" >&2
    exit 1
fi

if [[ "${1:-}" == --check ]]; then
    ownclip_resolve_signing_identity "$ownclip_local_signing_name"
    printf 'Local signing identity: %s (%s)\n' "$signing_name" "$signing_hash"
    exit 0
fi

# Never replace an existing certificate: a replacement would invalidate grants.
if certificate_lookup=$(/usr/bin/security find-certificate -c "$ownclip_local_signing_name" 2>&1); then
    if ! ownclip_resolve_signing_identity "$ownclip_local_signing_name"; then
        printf 'An existing OwnClip certificate is unusable. Restore its original private key or repair its Code Signing trust in Keychain Access; it will not be regenerated.\n' >&2
        exit 1
    fi
    printf 'Reusing local signing identity: %s (%s)\n' "$signing_name" "$signing_hash"
    exit 0
else
    lookup_status=$?
    # errSecItemNotFound (-25300) is exit status 44. Access failures must not
    # be mistaken for a missing certificate and create a replacement identity.
    if [[ "$lookup_status" != 44 ]]; then
        printf 'Cannot inspect the keychain; no certificate will be created.\n%s\n' "$certificate_lookup" >&2
        exit 1
    fi
fi

keychain=$(/usr/bin/security default-keychain -d user | /usr/bin/sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')
if [[ -z "$keychain" || ! -f "$keychain" ]]; then
    printf 'No default user keychain is available. Configure one in Keychain Access first.\n' >&2
    exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/ownclip-signing.XXXXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT
cat > "$work_dir/certificate.conf" <<EOF
[req]
distinguished_name = subject
prompt = no
[subject]
CN = $ownclip_local_signing_name
[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

printf 'Creating a persistent local signing certificate in the default user keychain.\n'
if ! /usr/bin/openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 \
    -config "$work_dir/certificate.conf" -extensions extensions \
    -keyout "$work_dir/private.key" -out "$work_dir/certificate.pem" 2> "$work_dir/openssl.log"; then
    cat "$work_dir/openssl.log" >&2
    exit 1
fi
certificate_password=$(/usr/bin/openssl rand -hex 24)
export OWNCLIP_P12_PASSWORD="$certificate_password"
/usr/bin/openssl pkcs12 -export -name "$ownclip_local_signing_name" \
    -inkey "$work_dir/private.key" -in "$work_dir/certificate.pem" \
    -out "$work_dir/identity.p12" -passout env:OWNCLIP_P12_PASSWORD
/usr/bin/security import "$work_dir/identity.p12" -k "$keychain" \
    -P "$certificate_password" -T /usr/bin/codesign
unset OWNCLIP_P12_PASSWORD certificate_password

# Trust only for code signing, in the current user's trust store (no sudo).
# macOS may ask the user to approve the keychain/trust change.
/usr/bin/security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$work_dir/certificate.pem"
ownclip_resolve_signing_identity "$ownclip_local_signing_name"
printf 'Local signing identity ready: %s (%s)\n' "$signing_name" "$signing_hash"
printf 'Keep this certificate and its private key for all future OwnClip builds.\n'
