# Contributing to Pulse Notch

Pulse Notch is a personal macOS project, but focused issues and pull requests are
welcome.

## Before you start

- Open an issue before a substantial feature or architectural change.
- Keep changes small and tied to a concrete user need.
- Prefer Apple frameworks and existing project patterns over new dependencies.
- Never include credentials, personal data, generated build output, or signing assets.

## Development

Requirements:

- macOS 14 or newer.
- Swift 6 or newer.

Build the app without opening it:

```sh
./Scripts/run-app.sh --no-open
```

Run the complete test suite:

```sh
swift test
```

## Pull requests

- Explain the user-facing problem and the chosen solution.
- Add proportionate tests for behavior changes and regression tests for bug fixes.
- Keep UI work native to macOS and consider VoiceOver, keyboard use, Reduce Motion,
  increased contrast, and reduced transparency.
- Document any new permission, data retention, refresh, failure, and disconnect behavior.
- Confirm that the app builds without new warnings and that `swift test` passes.
