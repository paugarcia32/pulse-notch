#!/bin/zsh
#
# Prepares a development build of Pulse Notch for the AI Agent's computer use.
#
# macOS does not let any script grant Accessibility or Screen Recording: the user
# must approve them in System Settings. This script makes that approval stick by
# signing development builds with a stable local identity (ad-hoc signatures change
# on every build, so macOS forgets the grant), rebuilds, and opens the right
# Settings pane. It clears stale grants only when it creates the identity, or when
# run with --reset.

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
app_path="$repository_root/.build/Pulse Notch.app"
identity="Pulse Notch Development"
bundle_identifier=$(plutil -extract CFBundleIdentifier raw "$repository_root/Sources/PulseNotchApp/Info.plist")

created_identity=false
reset_grants=false
[[ "${1:-}" == "--reset" ]] && reset_grants=true

if ! security find-identity -v -p codesigning | grep -q "\"$identity\""; then
    created_identity=true
    print "Creating the local code-signing identity \"$identity\"…"
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    cat > "$work/openssl.cnf" <<CONFIG
[req]
distinguished_name = subject
x509_extensions = codesign
prompt = no
[subject]
CN = $identity
[codesign]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONFIG
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -config "$work/openssl.cnf" -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
    password=$(/usr/bin/openssl rand -hex 16)
    /usr/bin/openssl pkcs12 -export -legacy -inkey "$work/key.pem" -in "$work/cert.pem" \
        -name "$identity" -passout "pass:$password" -out "$work/identity.p12" 2>/dev/null \
        || /usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
            -name "$identity" -passout "pass:$password" -out "$work/identity.p12"
    security import "$work/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
        -P "$password" -T /usr/bin/codesign
    print "macOS will ask for your password to trust the certificate for code signing."
    security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$work/cert.pem"
fi

print "Quitting running copies of Pulse Notch…"
osascript -e "tell application id \"$bundle_identifier\" to quit" 2>/dev/null || true
sleep 2

print "Building and signing with \"$identity\"…"
PULSE_NOTCH_CODESIGN_IDENTITY=$identity "$script_directory/build-app.sh" debug >/dev/null

# Grants made for the old ad-hoc signature no longer match, so clear them once when
# switching to the stable identity. Later runs keep the user's approval.
if [[ "$created_identity" == true || "$reset_grants" == true ]]; then
    print "Clearing stale Accessibility and Screen Recording entries for $bundle_identifier…"
    print "(Any other copy of Pulse Notch with this bundle ID will need to be approved again.)"
    tccutil reset Accessibility "$bundle_identifier" || true
    tccutil reset ScreenCapture "$bundle_identifier" || true
else
    print "Keeping existing permissions (the signature is unchanged). Use --reset to clear them."
fi

open "$app_path"
sleep 2
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

cat <<MESSAGE

Last step (macOS requires it to be done by you):
  1. In Accessibility, turn on "Pulse Notch" (use + to add $app_path if it is not listed).
  2. Optional, for screenshots: Privacy & Security → Screen Recording → turn on Pulse Notch,
     then quit and reopen Pulse Notch.

From now on rebuilds keep these permissions, because the signature stays the same.
MESSAGE
