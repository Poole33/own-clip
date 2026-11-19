#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
output_dir="$project_dir/dist"
architecture="${OWNCLIP_ARCH:-$(uname -m)}"
source "$project_dir/Tools/signing-common.sh"
source "$project_dir/Tools/source-files.sh"
ownclip_collect_sources "$project_dir/Sources"
signing_identity="${OWNCLIP_SIGN_IDENTITY-$ownclip_local_signing_name}"
notary_profile="${OWNCLIP_NOTARY_PROFILE:-}"

case "$architecture" in
    arm64|x86_64) ;;
    *) printf 'Unsupported macOS architecture: %s\n' "$architecture" >&2; exit 1 ;;
esac
case "${1:-}" in
    ''|--app-only) ;;
    *) printf 'Usage: %s [--app-only]\n' "$0" >&2; exit 1 ;;
esac
if [[ $# -gt 1 ]]; then
    printf 'Usage: %s [--app-only]\n' "$0" >&2
    exit 1
fi
ownclip_resolve_signing_identity "$signing_identity"
developer_id=false
signing_options=(--force --sign "$signing_hash")
if [[ "$signing_name" == 'Developer ID Application:'* ]]; then
    developer_id=true
    signing_options+=(--options runtime --timestamp)
else
    signing_options+=(--timestamp=none)
fi
if [[ -n "$notary_profile" ]] && { [[ "${1:-}" == --app-only ]] || [[ "$developer_id" == false ]]; }; then
    printf 'Notarization requires a full DMG build and a Developer ID Application signing identity.\n' >&2
    exit 1
fi
printf 'Signing OwnClip with %s (%s)\n' "$signing_name" "$signing_hash"
work_dir="$(mktemp -d "$project_dir/.build.XXXXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT

export CLANG_MODULE_CACHE_PATH="$project_dir/.build/module-cache"
app="$work_dir/OwnClip.app"
executable="$app/Contents/MacOS/OwnClip"
mkdir -p -- "$app/Contents/MacOS" "$app/Contents/Resources" "$output_dir"
# Keep compiler side products inside the temporary build directory as well.
cd -- "$work_dir"
/usr/bin/xcrun swiftc -target "$architecture-apple-macosx14.0" -swift-version 5 -O -whole-module-optimization -g \
    -module-name OwnClip -lsqlite3 "${ownclip_sources[@]}" -o "$executable"
symbols="$executable.dSYM"
test -f "$symbols/Contents/Resources/DWARF/OwnClip"
/bin/mv -- "$symbols" "$work_dir/OwnClip.app.dSYM"
/usr/bin/strip -x "$executable"
/usr/bin/install -m 644 "$project_dir/Resources/Info.plist" "$app/Contents/Info.plist"
/usr/bin/plutil -lint "$app/Contents/Info.plist"
/usr/bin/xcrun swiftc -swift-version 5 "$project_dir/Sources/UI/OwnClipIcon.swift" \
    "$project_dir/Tools/make-icon.swift" -o "$work_dir/make-icon"
iconset="$work_dir/OwnClip.iconset"
mkdir -- "$iconset"
for icon_size in 16 32 128 256 512; do
    "$work_dir/make-icon" "$iconset/icon_${icon_size}x${icon_size}.png" "$icon_size"
    "$work_dir/make-icon" "$iconset/icon_${icon_size}x${icon_size}@2x.png" "$((icon_size * 2))"
done
/usr/bin/iconutil -c icns "$iconset" -o "$app/Contents/Resources/OwnClip.icns"
/usr/bin/codesign "${signing_options[@]}" "$app"
/usr/bin/codesign --verify --strict "$app"

if [[ "${1:-}" != --app-only ]]; then
    staging="$work_dir/disk"
    mkdir -- "$staging"
    /usr/bin/ditto "$app" "$staging/OwnClip.app"
    /bin/ln -s /Applications "$staging/Applications"
    dmg="$work_dir/OwnClip.dmg"
    /usr/bin/hdiutil create -quiet -ov -srcfolder "$staging" -volname OwnClip -format UDZO "$dmg"
    if [[ "$developer_id" == true ]]; then
        /usr/bin/codesign --sign "$signing_hash" --timestamp "$dmg"
    fi
    if [[ -n "$notary_profile" ]]; then
        result="$work_dir/notarization.plist"
        /usr/bin/xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait --output-format plist > "$result"
        /usr/bin/plutil -p "$result"
        test "$(/usr/bin/plutil -extract status raw -o - "$result")" = Accepted
        /usr/bin/xcrun stapler staple "$dmg"
        /usr/bin/xcrun stapler validate "$dmg"
    fi
    /usr/bin/hdiutil verify -quiet "$dmg"
    /bin/mv -f -- "$dmg" "$output_dir/OwnClip.dmg"
fi

/bin/rm -rf -- "$output_dir/OwnClip.app" "$output_dir/OwnClip.app.dSYM"
/bin/mv -- "$app" "$output_dir/OwnClip.app"
/bin/mv -- "$work_dir/OwnClip.app.dSYM" "$output_dir/OwnClip.app.dSYM"
printf 'OwnClip built in %s\n' "$output_dir"
