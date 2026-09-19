# Releasing Pulse Notch

Pulse Notch releases are built and published by GitHub Actions from version tags.

## One-time setup

Create a fine-grained GitHub personal access token with access only to
`paugarcia32/homebrew-tap` and grant it `Contents: Read and write`. Add it to the
`pulse-notch` repository as an Actions secret named `HOMEBREW_TAP_TOKEN`.

## Publish a release

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in
   `Sources/PulseNotchApp/Info.plist`.
2. Commit the version change and push it to `main`.
3. Wait for CI to pass.
4. Create and push a tag matching the app version:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

The release workflow validates the version, runs the full test suite, builds and
verifies the DMG, publishes the DMG and its SHA-256 checksum to GitHub Releases,
and updates the version and checksum in the Homebrew cask.

Release tags must use the exact `vX.Y.Z` format. The workflow rejects a tag that
does not match `CFBundleShortVersionString`.
