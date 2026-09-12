# Pulse Notch

Pulse Notch is a native macOS app that turns the display notch into an ambient,
expandable surface for calendar events, GitHub activity, coding-agent status, and
media controls.

The repository currently contains the first executable product slice:

- A SwiftUI macOS preview of collapsed and expanded notch states.
- A selectable week showing every Calendar event for the chosen day.
- An amber Calendar icon when the next event starts within ten minutes.
- A Join action for Google Meet, Zoom, Teams, and Webex links.
- Local detection of running Codex, Claude Code, Cursor Agent, Antigravity, and OpenCode
  sessions.
- Calendar and coding-agent pages navigable with a two-finger horizontal swipe,
  also available with Command-1 and Command-2.
- Animated running and recently-completed agent indicators in the collapsed notch.
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

On first launch, macOS asks for full Calendar access. Pulse Notch reads upcoming
event metadata locally, refreshes it every 30 seconds, and does not persist it.

Coding-agent detection reads local process and session metadata every two seconds.
It does not persist process data or require credentials. Completed agents remain
visible for five minutes, while their collapsed notification is cleared as soon as
the notch opens. Cursor's standalone `cursor-agent` CLI is supported; Cursor editor
chats cannot currently be distinguished reliably from the editor's background
processes.

For active sessions, Pulse Notch reads the working directory and Git branch locally
when the agent exposes them. It does not read or show coding-agent prompts or thread
titles. This metadata stays in memory; directory and branch lookups are cached for
thirty seconds while the agent is running.

The GitHub page uses the official `gh` CLI session you have already authenticated with
(`gh auth login`). It reads up to 100 open pull requests authored by you, including
their review decision and GitHub Actions checks, refreshes every thirty seconds, and
keeps the result in memory only. A workflow appears as a runner only while it is
running or for five minutes after it finishes; completions appear in the collapsed
notch until it is opened. It does not read, save, or log a token.

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

This is an intentionally small foundation. The preview uses a regular app window
while the domain model and interaction are established. A later milestone will
introduce the non-activating AppKit panel, runtime display geometry, and
multi-display behavior required by the real notch surface.
