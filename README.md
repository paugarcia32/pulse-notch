# Pulse Notch

Pulse Notch is a native macOS app that turns the display notch into an ambient,
expandable surface for calendar events, GitHub activity, coding-agent status, and
media controls.

The repository currently contains the first executable product slice:

- A non-activating AppKit panel anchored to the active display's notch area, with
  public-framework support for Spaces, full-screen apps, and display changes.
- A selectable week showing every Calendar event for the chosen day.
- An amber Calendar icon when the next event starts within ten minutes.
- A Join action for Google Meet, Zoom, Teams, and Webex links.
- Local detection of running Codex, Claude Code, Cursor Agent, Antigravity, and OpenCode
  sessions.
- Calendar and coding-agent pages navigable with a two-finger horizontal swipe,
  also available with Command-1 and Command-2.
- Animated running and recently-completed agent indicators in the collapsed notch.
- Animated indicators for active browser downloads in a configurable folder.
- A temporary charging activity with the current battery percentage when external power connects.
- Temporary volume and display-brightness activities that replace collapsed indicators.
- A temporary Bluetooth-headphones connection activity, with a battery glyph when headphones connect.
- A configurable Media page with artwork, transport controls, and a compact artwork/equalizer indicator.
- Live Codex five-hour and weekly usage gauges on the coding-agent page.
- Agent cards with project, Git branch, and elapsed-session context when available.
- A GitHub page for your open and draft pull requests, with comments, passed checks,
  review state, and individual GitHub Actions runners.
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

On first launch, macOS asks for full Calendar access. While the Calendar page is
enabled, Pulse Notch reads upcoming event metadata locally, refreshes it every 30
seconds, and does not persist it.

While the Coding Agents page is enabled, detection reads local process and session
metadata every two seconds. It does not persist process data or require credentials.
Completed agents remain visible for five minutes, while their collapsed notification
is cleared as soon as the notch opens. Cursor's standalone `cursor-agent` CLI is
supported; Cursor editor chats cannot currently be distinguished reliably from the
editor's background processes.

Pulse Notch reads the internal battery's charge and power-source state locally once
per second. Connecting external power temporarily replaces collapsed indicators with
a charging icon and percentage; its duration and visibility are configurable in
Settings > General. Battery state is kept only in memory and needs
no permission.

Volume changes use a local Core Audio listener, so the activity follows each key
press rather than waiting for a polling interval. Display brightness observes
CoreBrightness changes when macOS publishes them, with a short local polling
fallback for the built-in display. IOKit remains the first reader and the local
CoreBrightness diagnostic handles Macs where IOKit does not expose that value.
Their visibility and duration use the same Settings > General controls as
charging. External displays without a compatible brightness control remain quiet.

Bluetooth headphones are detected locally from the public IOBluetooth connection
state. A new connection temporarily replaces collapsed indicators with headphones
on the left and a battery glyph on the right; its visibility and duration are also
configurable in Settings > General. Device names and addresses are never shown,
persisted, or logged. macOS does not provide a generic public battery-level API for
all Bluetooth headphones, so Pulse Notch matches the connected device against
locally reported accessory battery levels from IOKit, `system_profiler`, and
`pmset`. When neither source reports a value, it uses a neutral battery glyph
rather than inventing a percentage. The Testing view includes a 72% example to
verify the filled battery treatment.

Downloads monitoring defaults to the user's Downloads folder and can be pointed at
another folder in Settings. It observes browser temporary files locally and never
displays or persists download file names or paths. The feature can be disabled at
any time.

While the Media page is enabled, media playback reads the active system Now Playing
item locally, including Spotify and browser players such as YouTube when they publish
a system media session. It keeps its title, artist, artwork, and progress in memory
only. Its compact indicator can be disabled below the Media page in Settings > Pages;
disabling the page also hides the indicator and stops playback polling. macOS has no
public API for reading another app's Now Playing item, so the local bridge is optional
at runtime; when it is unavailable, the page shows an empty state.

Settings > Pages can enable dynamic pages. In that mode, configured pages keep their
order but appear only when relevant: Calendar has a current or upcoming event today,
an agent is running, GitHub has an open pull request or running Action, or media is
playing or was paused within the last five minutes. When disabled, every configured
page remains available as usual.

For active sessions, Pulse Notch reads the working directory and Git branch locally
when the agent exposes them. It does not read or show coding-agent prompts or thread
titles. This metadata stays in memory; directory and branch lookups are cached for
thirty seconds while the agent is running.

While enabled, the GitHub page uses the official `gh` CLI session you have already
authenticated with (`gh auth login`). It reads up to 100 open pull requests authored
by you, including their review decision and GitHub Actions checks, refreshes every
thirty seconds, and keeps the result in memory only. A workflow appears as a runner
only while it is running or for five minutes after it finishes; completions appear in
the collapsed notch until it is opened. It does not read, save, or log a token.

When the coding-agent page is visible, Pulse Notch asks the locally installed Codex
App Server for the current quota windows once per minute. This reuses Codex's own
login, does not read or store its credentials, and keeps the returned percentages
in memory only. Claude Code can optionally share its usage through its official
status-line input. Antigravity's locally installed `agy` CLI is queried with its
official non-interactive `/usage` command; its credentials remain in the system
Keychain. Cursor exposes its monthly pools in its dashboard rather than a CLI
usage API. OpenCode can use many providers, so its limits are owned by the
configured provider and are not represented as one OpenCode quota.

To opt into Claude Code usage, set its status-line command to the following in
`/statusline` (replace the path if Pulse Notch is installed elsewhere):

```sh
/path/to/PulseNotch.app/Contents/MacOS/PulseNotchClaudeBridge
```

Claude Code passes its local session JSON to that command after each response.
Pulse Notch stores only the quota fields in `~/.claude/pulse-notch-usage.json`;
no credential or transcript is read. This is available for Claude.ai Pro/Max
accounts after the session's first API response.

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

This is an intentionally small foundation. Pulse Notch uses public AppKit APIs to
anchor one non-activating surface to the selected display. It follows the physical
notch dimensions when macOS exposes them and falls back to a compact centered
surface on displays without a notch.

In Settings > General > Display, choose a specific display or follow the display
under the pointer. External displays can use a compact capsule or rectangular
notch; the physical-notch appearance is always preserved on notched displays.
Each external style uses the target display's actual menu-bar height.
