# Pulse Notch

Pulse Notch is a native macOS app that turns the display notch into an ambient,
expandable surface for calendar events, GitHub activity, coding-agent status, and
media controls.

The repository currently contains the first executable product skeleton:

- A SwiftUI macOS preview of collapsed and expanded notch states.
- A platform-independent domain module.
- Deterministic unit tests for activity ordering.
- Shared engineering rules for coding agents.

## Requirements

- macOS 14 or newer.
- Swift 6 or newer.

## Run

```sh
swift run PulseNotch
```

## Test

```sh
swift test
```

## Current Scope

This is an intentionally small foundation. The preview uses a regular app window
while the domain model and interaction are established. A later milestone will
introduce the non-activating AppKit panel, runtime display geometry, and
multi-display behavior required by the real notch surface.
