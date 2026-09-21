# Releasing Pulse Notch

Pulse Notch releases are built and published by GitHub Actions from version tags.

## One-time setup

Create a fine-grained GitHub personal access token with access only to
`paugarcia32/homebrew-tap` and grant it `Contents: Read and write`. Add it to the
`pulse-notch` repository as an Actions secret named `HOMEBREW_TAP_TOKEN`.

## Publish a release

Prepare a major, minor, or patch release with:

```sh
./Scripts/prepare-release.sh
```

The script updates `CFBundleShortVersionString` and `CFBundleVersion`, runs the
tests, commits and pushes `main`, then creates and pushes the release tag. It
must run from `main` with no pending changes to `Info.plist` and asks for
confirmation before making changes.

For example, to publish version `0.1.1` manually:

1. Update both values in `Sources/PulseNotchApp/Info.plist`:

   ```text
   CFBundleShortVersionString: 0.1.0 → 0.1.1
   CFBundleVersion:            1     → 2
   ```

2. Run the tests and commit the version change:

   ```sh
   swift test
   git add Sources/PulseNotchApp/Info.plist
   git commit -m "chore: prepare release 0.1.1"
   git push origin main
   ```

3. Create and push an annotated tag matching the app version:

   ```sh
   git tag -a v0.1.1 -m "Pulse Notch 0.1.1"
   git push origin v0.1.1
   ```

   Replace `0.1.1` in the commands with the version being released. Do not reuse
   an existing tag or create a second release manually.

4. Open the GitHub Actions run for the `Release` workflow and wait for it to
   finish. It publishes the DMG and checksum to the existing tag's GitHub Release
   and updates the Homebrew cask automatically.

The release workflow validates the version, runs the full test suite, builds and
verifies the DMG, publishes the DMG and its SHA-256 checksum to GitHub Releases,
and updates the version and checksum in the Homebrew cask.

Release tags must use the exact `vX.Y.Z` format. The workflow rejects a tag that
does not match `CFBundleShortVersionString`.

After a successful release, users can update an existing Homebrew installation with:

```sh
brew update
brew upgrade --cask pulse-notch
```

If the workflow fails while pushing to `homebrew-tap` with HTTP 403, the
`HOMEBREW_TAP_TOKEN` does not have `Contents: Read and write` access to that
repository. Replace the Actions secret with a token that has that access, then
rerun the failed workflow; do not create another tag.
