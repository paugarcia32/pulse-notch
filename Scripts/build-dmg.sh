#!/bin/zsh

set -euo pipefail

if (( $# > 0 )); then
    print -u2 "Usage: $0"
    exit 2
fi

script_directory=${0:A:h}
repository_root=${script_directory:h}
info_plist_path="$repository_root/Sources/PulseNotchApp/Info.plist"
app_path="$repository_root/.build/Pulse Notch.app"
distribution_directory="$repository_root/dist"
version=$(plutil -extract CFBundleShortVersionString raw "$info_plist_path")
dmg_name="PulseNotch-$version.dmg"
dmg_path="$distribution_directory/$dmg_name"
checksum_path="$dmg_path.sha256"
staging_directory=$(mktemp -d)

cleanup() {
    rm -rf "$staging_directory"
}
trap cleanup EXIT

"$script_directory/build-app.sh" release

mkdir -p "$distribution_directory"
rm -f "$dmg_path" "$checksum_path"
ditto "$app_path" "$staging_directory/Pulse Notch.app"
ln -s /Applications "$staging_directory/Applications"

hdiutil create \
    -volname "Pulse Notch" \
    -srcfolder "$staging_directory" \
    -format UDZO \
    -ov \
    "$dmg_path"

hdiutil verify "$dmg_path"
(
    cd "$distribution_directory"
    shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
)

print "$dmg_path"
print "$checksum_path"
