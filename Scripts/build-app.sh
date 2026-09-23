#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
configuration=${1:-debug}
app_path="$repository_root/.build/Pulse Notch.app"
contents_path="$app_path/Contents"
resource_bundle_name="PulseNotch_PulseNotchApp.bundle"
info_plist_path="$repository_root/Sources/PulseNotchApp/Info.plist"
icon_path="$repository_root/Sources/PulseNotchApp/Resources/PulseNotch.icns"
media_remote_adapter_path="$repository_root/Vendor/MediaRemoteAdapter"
bundle_identifier=$(plutil -extract CFBundleIdentifier raw "$info_plist_path")

if (( $# > 1 )); then
    print -u2 "Usage: $0 [debug|release]"
    exit 2
fi

case "$configuration" in
    debug|release) ;;
    *)
        print -u2 "Unknown configuration: $configuration"
        exit 2
        ;;
esac

swift build \
    --package-path "$repository_root" \
    --configuration "$configuration" \
    --product PulseNotch

swift build \
    --package-path "$repository_root" \
    --configuration "$configuration" \
    --product PulseNotchClaudeBridge

swift build \
    --package-path "$repository_root" \
    --configuration "$configuration" \
    --product PulseNotchUpdater

binary_directory=$(swift build \
    --package-path "$repository_root" \
    --configuration "$configuration" \
    --show-bin-path)
resource_bundle_path="$binary_directory/$resource_bundle_name"

if [[ ! -d "$resource_bundle_path" ]]; then
    print -u2 "Missing resource bundle: $resource_bundle_path"
    exit 1
fi

if [[ ! -d "$media_remote_adapter_path" ]]; then
    print -u2 "Missing MediaRemote adapter: $media_remote_adapter_path"
    exit 1
fi

rm -rf "$app_path"
mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
install -m 755 "$binary_directory/PulseNotch" "$contents_path/MacOS/PulseNotch"
install -m 755 "$binary_directory/PulseNotchClaudeBridge" "$contents_path/MacOS/PulseNotchClaudeBridge"
install -m 755 "$binary_directory/PulseNotchUpdater" "$contents_path/MacOS/PulseNotchUpdater"
install -m 644 "$info_plist_path" "$contents_path/Info.plist"
install -m 644 "$icon_path" "$contents_path/Resources/PulseNotch.icns"
ditto "$resource_bundle_path" "$contents_path/Resources/$resource_bundle_name"
ditto "$media_remote_adapter_path" "$contents_path/Resources/MediaRemoteAdapter"

codesign \
    --force \
    --sign - \
    "$contents_path/Resources/MediaRemoteAdapter/MediaRemoteAdapter.framework"

codesign \
    --force \
    --sign - \
    --identifier "$bundle_identifier.ClaudeBridge" \
    "$contents_path/MacOS/PulseNotchClaudeBridge"

codesign \
    --force \
    --sign - \
    --identifier "$bundle_identifier.Updater" \
    "$contents_path/MacOS/PulseNotchUpdater"

codesign \
    --force \
    --sign - \
    --identifier "$bundle_identifier" \
    "$app_path"

codesign --verify --deep --strict --verbose=2 "$app_path"
print "$app_path"
