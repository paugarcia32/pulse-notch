
<p align="center">
  <img src="Docs/Assets/pulse-notch-logo.png" width="128" height="128" alt="Pulse Notch app icon">
</p>

<h1 align="center">Pulse Notch</h1>

<p align="center">
  A quiet, expandable activity surface for the MacBook notch.
</p>

<p align="center">
  Pulse Notch started as a personal tool for my own workflow: I wanted the notch
  to tell me when coding agents and GitHub Actions finished, while keeping my next
  calendar event close without adding more notification noise.
</p>

## Demo

<p align="center">
  <a href="Docs/Assets/pulse-notch-demo.mov">
    <img width="800" height="389" alt="pulse-notch-demo" src="https://github.com/user-attachments/assets/599cfd5e-b757-4b37-b5d2-62e22235243f" />
  </a>
</p>


## Installation

Install with Homebrew:

```sh
brew install --cask paugarcia32/tap/pulse-notch
```

Alternatively, download the DMG from the
[latest GitHub release](https://github.com/paugarcia32/pulse-notch/releases/latest)
and drag Pulse Notch to Applications.

Pulse Notch is ad-hoc signed and not notarized. On first launch, macOS may require
allowing it from System Settings > Privacy & Security.

To build from source:

```sh
git clone https://github.com/paugarcia32/pulse-notch.git
cd pulse-notch
./Scripts/run-app.sh
```

The script builds, ad-hoc signs, registers, and opens `.build/Pulse Notch.app`.
Launching the executable directly with `swift run PulseNotch` is not supported
because macOS cannot reliably associate privacy permissions with a standalone
SwiftPM executable.

## System requirements

- macOS 14 Sonoma or newer.
- An Apple Silicon Mac. Intel builds are not currently distributed.
- Swift 6 or newer when building from source.
- A Mac with or without a physical notch. External displays use a compact fallback.
- The GitHub CLI (`gh`) is optional and only required for GitHub activity.

## What it shows

- A prioritized summary of the next event, active work, agent usage limits, media,
  and anything that needs attention.
- Upcoming Calendar events, including meeting links and configurable reminders.
- Running and recently completed Codex, Claude Code, Cursor Agent, Antigravity,
  and OpenCode sessions.
- Open pull requests, reviews, checks, and active GitHub Actions.
- Active browser downloads and Homebrew operations.
- Now Playing controls, artwork, and playback progress.
- Charging, volume, brightness, and Bluetooth-headphone activities.
- Stopwatch and timer activity.
- Multiple displays, Spaces, full-screen apps, keyboard shortcuts, and configurable
  collapsed indicators.

Pulse Notch is not intended to replace Notification Center. It keeps a small number
of useful, time-sensitive signals visible and stays out of the way until expanded.

## Privacy and permissions

Pulse Notch processes activity locally and does not include telemetry.

- Calendar access is requested only when Calendar features are enabled. Event data
  stays in memory and refreshes every 30 seconds.
- Coding-agent detection reads local process and session metadata, never prompts or
  conversation contents.
- GitHub activity uses the authenticated official `gh` CLI and never reads or stores
  its token.
- Downloads monitoring observes the selected local folder and can be disabled.
- Battery, Bluetooth, volume, brightness, and media state are read locally and kept
  in memory.
- Update checks query the public GitHub Releases API at most once per day and can be
  disabled in Settings.
- No credentials are stored by Pulse Notch.

Each integration can be disabled from Settings. macOS requests Calendar, Bluetooth,
or Downloads access only when the corresponding feature needs it.

## Development

Build and open the app without launching it automatically:

```sh
./Scripts/run-app.sh --no-open
```

Build the ad-hoc signed release DMG and its SHA-256 checksum:

```sh
./Scripts/build-dmg.sh
```

The release artifacts are written to `dist/`.
See [Docs/RELEASING.md](Docs/RELEASING.md) for the release process.

Run the test suite:

```sh
swift test
```

The project uses Swift 6, SwiftUI, AppKit where needed, Swift Package Manager, strict
concurrency checking, and Swift Testing. Domain behavior lives in `PulseNotchCore`;
macOS UI and integrations live in `PulseNotchApp`.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before
opening an issue or pull request.

## Inspiration

Pulse Notch is heavily inspired by [Alcove](https://tryalcove.com/),
[Boring Notch](https://github.com/TheBoredTeam/boring.notch), and
[Atoll](https://github.com/Atoll-Labs/Atoll). Those apps helped establish what a
native notch utility can feel like; Pulse Notch builds on that idea with the agent,
GitHub Actions, usage-limit, and workflow features that matter most to my own setup.
