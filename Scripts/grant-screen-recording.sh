#!/bin/zsh
#
# Guides the Screen Recording approval the AI Agent needs for screenshots.
#
# macOS does not let scripts grant Screen Recording; the user must turn it on in
# System Settings. This script opens that pane, waits for the approval, and then
# restarts Pulse Notch, because macOS applies a new Screen Recording grant only
# to processes launched afterwards.

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
app_path="$repository_root/.build/Pulse Notch.app"
bundle_identifier=$(plutil -extract CFBundleIdentifier raw "$repository_root/Sources/PulseNotchApp/Info.plist")

if [[ ! -d "$app_path" ]]; then
    print -u2 "Build Pulse Notch first: ./Scripts/setup-computer-use.sh"
    exit 1
fi

open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
cat <<MESSAGE
In the Screen Recording list that just opened, turn on "Pulse Notch".
If it is not listed, click +, press ⇧⌘G, and choose:
  $app_path

MESSAGE
read "?Press Return once Pulse Notch is turned on… "

print "Restarting Pulse Notch so the permission takes effect…"
osascript -e "tell application id \"$bundle_identifier\" to quit" 2>/dev/null || true
while pgrep -f "$app_path/Contents/MacOS/PulseNotch" >/dev/null; do sleep 0.5; done
open "$app_path"
print "Done. Ask the agent to continue; it can now take screenshots."
