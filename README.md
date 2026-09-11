# Pulse Notch

Pulse Notch is a native macOS app that turns the display notch into an ambient,
expandable surface for calendar events, GitHub activity, coding-agent status, and
media controls.

The repository currently contains the first executable product slice:

- A SwiftUI macOS preview of collapsed and expanded notch states.
- A selectable week showing every Calendar event for the chosen day.
- An amber Calendar icon when the next event starts within ten minutes.
- A Join action for Google Meet, Zoom, Teams, and Webex links.
- A platform-independent domain module.
- Deterministic unit tests for activity ordering.
- Shared engineering rules for coding agents.

## Requirements

- macOS 14 or newer.
- Swift 6 or newer.

## Run

```sh
./Scripts/run-app.sh
```

The script builds and opens a local `PulseNotch.app`. Launching the executable
directly with `swift run PulseNotch` is not supported because macOS cannot
associate privacy permissions reliably with a standalone SwiftPM executable.

On first launch, macOS asks for full Calendar access. Pulse Notch reads upcoming
event metadata locally, refreshes it every 30 seconds, and does not persist it.

If a local rebuild invalidates the development permission, register the rebuilt
app, reset only its Calendar decision, and open it again with:

```sh
./Scripts/run-app.sh --reset-calendar-access
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
