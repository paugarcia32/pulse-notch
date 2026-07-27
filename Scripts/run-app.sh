#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
configuration=debug
app_path="$repository_root/.build/PulseNotch.app"
contents_path="$app_path/Contents"
executable_path="$contents_path/MacOS/PulseNotch"
info_plist_path="$repository_root/Sources/PulseNotchApp/Info.plist"
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

binary_directory=$(swift build \
    --package-path "$repository_root" \
    --configuration "$configuration" \
    --show-bin-path)

mkdir -p "$contents_path/MacOS"
install -m 755 "$binary_directory/PulseNotch" "$executable_path"
install -m 644 "$info_plist_path" "$contents_path/Info.plist"

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
