#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
configuration=debug
app_path="$repository_root/.build/Pulse Notch.app"
contents_path="$app_path/Contents"
executable_path="$contents_path/MacOS/PulseNotch"
claude_bridge_path="$contents_path/MacOS/PulseNotchClaudeBridge"
resource_bundle_name="PulseNotch_PulseNotchApp.bundle"
info_plist_path="$repository_root/Sources/PulseNotchApp/Info.plist"
icon_path="$repository_root/Sources/PulseNotchApp/Resources/PulseNotch.icns"
media_remote_adapter_path="$repository_root/Vendor/MediaRemoteAdapter"
launch_services_register="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
should_open=true
should_reset_calendar_access=false

for option in "$@"; do
    case "$option" in
        --no-open)
            should_open=false
            ;;
        --reset-calendar-access)
            should_reset_calendar_access=true
            ;;
        *)
            print -u2 "Unknown option: $option"
            exit 2
            ;;
    esac
done

swift build \
    --package-path "$repository_root" \
    --configuration "$configuration" \
    --product PulseNotch

swift build \
    --package-path "$repository_root" \
    --configuration "$configuration" \
    --product PulseNotchClaudeBridge

binary_directory=$(swift build \
    --package-path "$repository_root" \
    --configuration "$configuration" \
    --show-bin-path)

mkdir -p "$contents_path/MacOS"
install -m 755 "$binary_directory/PulseNotch" "$executable_path"
install -m 755 "$binary_directory/PulseNotchClaudeBridge" "$claude_bridge_path"
install -m 644 "$info_plist_path" "$contents_path/Info.plist"
mkdir -p "$contents_path/Resources"
install -m 644 "$icon_path" "$contents_path/Resources/PulseNotch.icns"
if [[ -d "$binary_directory/$resource_bundle_name" ]]; then
    ditto "$binary_directory/$resource_bundle_name" "$contents_path/Resources/$resource_bundle_name"
fi

if [[ -d "$media_remote_adapter_path" ]]; then
    mkdir -p "$contents_path/Resources"
    ditto "$media_remote_adapter_path" "$contents_path/Resources/MediaRemoteAdapter"
fi

codesign \
    --force \
    --sign - \
    --identifier com.pau.PulseNotch \
    "$app_path"

"$launch_services_register" -f "$app_path"

if [[ "$should_reset_calendar_access" == true ]]; then
    tccutil reset Calendar com.pau.PulseNotch
fi

if [[ "$should_open" == true ]]; then
    open "$app_path"
fi
