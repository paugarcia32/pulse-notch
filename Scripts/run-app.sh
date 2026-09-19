#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
app_path="$repository_root/.build/Pulse Notch.app"
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

"$script_directory/build-app.sh" debug
bundle_identifier=$(plutil -extract CFBundleIdentifier raw "$app_path/Contents/Info.plist")

"$launch_services_register" -f "$app_path"

if [[ "$should_reset_calendar_access" == true ]]; then
    tccutil reset Calendar "$bundle_identifier"
fi

if [[ "$should_open" == true ]]; then
    open "$app_path"
fi
