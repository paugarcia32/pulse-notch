
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
    <img width="1200" height="600" alt="pulse-notch-demo" src="https://github.com/user-attachments/assets/a644001a-adf5-4e1d-99da-a140b370f1ea" />
    />
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
  Codex and OpenCode subagents are grouped under their parent session; Claude Code
  subprocesses are grouped with their ancestor Claude Code process.
  OpenCode desktop activity is detected by read-only checks of unfinished responses
  in its local session database while the app is open. Pulse Notch stores no copy;
  closing OpenCode stops detection, and no extra permission is needed.
- Open pull requests, reviews, checks, and Actions from repositories selected in
  Settings, including workflows triggered by pushes and tags.
- Active browser downloads and Homebrew operations.
- Now Playing controls, artwork, and playback progress.
- Charging, volume, brightness-key presses, and Bluetooth-headphone activities.
  Automatic display-brightness adjustments do not trigger the notch indicator.
- Stopwatch and timer activity.
- Multiple displays, Spaces, full-screen apps, keyboard shortcuts, and configurable
  collapsed indicators.
- An optional AI Agent page for chat, desktop tasks, goals, and daily routines. It is
  off until you enable it.

Pulse Notch is not intended to replace Notification Center. It keeps a small number
of useful, time-sensitive signals visible and stays out of the way until expanded.

## AI Agent (optional)

The AI Agent page adds an assistant to the notch that can chat, operate apps on your
Mac, work toward goals with explicit completion criteria, and run daily or weekday
routines. It is **off by default**.

### Turn it on

1. Open **Settings → Pages → AI Agent** and select **Enable AI Agent**.
2. Open the notch and press **⌘8**, or use the page dots, to show the AI Agent page. It
   has four tabs: **Chat**, **Goals**, **Routines**, and **Settings**.
3. Finish setup in the page's **Settings** tab: choose providers, add keys or install
   local models, and optionally allow computer use.

The page uses a larger 640×520 surface, or less on small displays. It stays open when
the pointer leaves, so drafts and keyboard focus are kept. Page swipes are disabled so
text selection works. Esc or a click elsewhere collapses it without stopping running
work.

### How it works: the language model directs, the decision model operates

The agent uses two independently configured providers:

| Role | What it does | Hosted | Local |
|---|---|---|---|
| **Language model** (director) | Talks with you. Plans the task as natural-language steps such as "click the Save button" or "type into the message body". Supplies text to type. Reviews a screenshot after each step. Asks you for help when something looks wrong. | OpenRouter (API key and a model with tool support) | A managed `llama.cpp` server (MiMo-V2.6-Distill-Qwen-9B), or any OpenAI-compatible server |
| **Decision model** (operator) | For each step, chooses every concrete on-screen action from the visible controls. Checks sensitive actions for side effects. Decides when the step is done. Confirms goal completion. It never writes chat replies. | JEV through TypeSafe's System One API (API key) | Laya, managed by Pulse Notch or through an existing System One-compatible service |

All four combinations work. The loop follows the patterns of the most-used JEV
computer-use projects; see [Docs/AI-AGENT.md](Docs/AI-AGENT.md) for details.

- **JEV is recommended for computer use.** Published community evaluations found that
  the official Laya checkpoints choose on-screen controls much less reliably than JEV
  without fine-tuning. Laya remains available and fully local.
- Pulse Notch calls a configuration *fully local inference* only when both providers
  run on your Mac. Tasks that use online apps still reach the network.

### Choose providers

- **Hosted.**
  1. Choose *JEV* and *OpenRouter*, and paste your TypeSafe and OpenRouter keys. Keys
     are stored in the Keychain.
  2. Pick an OpenRouter model. The catalog shows tool and vision support, context
     length, and prices. You can also type a model ID.
  3. Confirm the privacy notice.
- **Managed local.**
  1. Choose *Laya (managed on this Mac)* and *Local model (managed on this Mac)*.
  2. Select **Install** for each component. Nothing downloads before you do.
     Components are reused offline and can be removed individually.
  3. Optionally, import a GGUF model and its vision projector.
- **Existing services.** Enter a Laya-compatible System One endpoint (for example
  `laya-serve`) and an OpenAI-compatible endpoint with a model ID. Keys are optional.

Then select **Test connection**. It sends a real decision request and checks that the
language model returns a **structured tool call** and can describe an image.

- Only models that pass the tool-call check can direct computer use.
- Only models that also pass the image check receive screenshots.
- If you skip the test, the first computer-use task runs it automatically.
- If the model fails, the agent tells you why. Choose a model marked "tools".

### Give Pulse Notch access to your Mac (computer use)

Computer use needs two macOS privacy permissions. macOS only lets you grant them
yourself in System Settings; no app or script can grant them.

| Permission | Required? | Used for |
|---|---|---|
| **Accessibility** | Yes | Reading the controls in the frontmost window, and clicking, typing, pressing keys, and scrolling |
| **Screen Recording** | Optional | Screenshots, so a vision-capable language model can check that the work is on track. Screenshots stay in memory and are never saved. |

#### Installed app (Homebrew or DMG)

1. On the AI Agent page, open **Settings** and turn on **Allow computer use**.
   macOS shows the Accessibility prompt.
2. Choose **Open System Settings**. In **Privacy & Security → Accessibility**, turn
   on **Pulse Notch**. If it is not listed, click **+**, choose
   `/Applications/Pulse Notch.app`, and turn it on.
3. Optional, for screenshots: back on the AI Agent Settings tab, select **Request**
   next to *Screen Recording*. That adds Pulse Notch to **Privacy & Security →
   Screen & System Audio Recording**. Turn it on there, then quit and reopen Pulse
   Notch; macOS applies this permission only after a restart.
4. The *Accessibility* and *Screen Recording* rows in the Settings tab turn green
   when the permissions are active.

#### A build from source

Development builds are ad-hoc signed by default. The signature changes on every
build, so macOS forgets the permissions after each rebuild and reports "Pulse Notch
needs Accessibility permission to control apps". Two scripts make the approval stick:

1. Run the setup script once:

   ```sh
   ./Scripts/setup-computer-use.sh
   ```

   It does the following:
   - creates a local code-signing identity named "Pulse Notch Development" in your
     login keychain (macOS asks for your password to trust it for code signing);
   - rebuilds and signs the app with that identity; `build-app.sh` uses it
     automatically from then on, so later builds keep their permissions;
   - clears stale Accessibility and Screen Recording entries for the bundle ID;
   - launches the build and opens the Accessibility pane.

   Later runs keep existing permissions. Pass `--reset` to clear them.
2. In **Accessibility**, turn on **Pulse Notch**. If it is not listed, click **+**,
   press **⇧⌘G**, and choose `.build/Pulse Notch.app` in the repository.
3. For screenshots, run:

   ```sh
   ./Scripts/grant-screen-recording.sh
   ```

   It opens **Screen & System Audio Recording** and waits while you turn on Pulse
   Notch (add `.build/Pulse Notch.app` with **+** if needed). Then it restarts the app.

> **Two copies with the same bundle ID.** If Pulse Notch is also installed in
> `/Applications`, macOS may relaunch that copy instead of your build, for example
> after *Quit & Reopen* in System Settings or at login. The AI Agent page then seems
> to disappear. Quit it and open `.build/Pulse Notch.app` again, or rename the
> installed copy while you test. Permissions are granted per copy.

To revoke access, turn Pulse Notch off in the same System Settings panes, or turn
off *Allow computer use*.

### Using computer use

- Ask in **Chat**, for example "Open Telegram and read me the last message". You can
  also create a **Goal** with completion criteria, or schedule a **Routine**.
- The run's timeline shows each step:
  - the decision model's choice and confidence;
  - risk checks;
  - executed actions and whether the screen changed.
- Runs are **autonomous** by default. **Supervised** mode asks you to approve each
  action. You can deny or allow specific apps by bundle identifier.
- **Limits.** A run is limited to 50 actions or 10 minutes by default; this is
  editable per goal and routine. After two failed replans, a run pauses with an
  explanation.
- **Queueing and waiting.** One desktop task runs at a time; others queue. The agent
  waits while the Mac is locked or asleep, and while you type in its composer, so it
  never types into its own UI.
- **Stopping.** Use **Pause**, **Resume**, and **Stop** on any run, or the global
  emergency stop **⌃⌥⌘.** (configurable under Shortcuts). Stopping prevents further
  actions and cancels inference. It does not undo completed actions.

### Goals and routines

- **Goals.** Saving a goal does not start it; choose **Run**. A goal completes only
  when the decision model confirms that the observed screen satisfies its criteria.
  The evidence is shown with the result.
- **Routines.** Each routine uses an IANA time zone, your current one by default. It
  runs while Pulse Notch is open, even with the notch collapsed, at most once per
  occurrence, including across daylight-saving changes.
- **Missed occurrences.** Occurrences missed while the Mac slept or Pulse Notch was
  closed appear with **Run now**. They are never replayed automatically.
- **Interrupted runs.** Runs interrupted by quitting are marked for review, not
  repeated.
- **Launch at login.** Use the existing *Open at login* setting.

## Privacy and permissions

Pulse Notch processes activity locally and does not include telemetry. The optional
AI Agent sends data only to the providers you configure, as described below.

- Calendar access is requested only when Calendar features are enabled. Event data
  stays in memory and refreshes every 30 seconds.
- Coding-agent detection reads local process and session metadata, never prompts or
  conversation contents.
- GitHub activity refreshes every 30 seconds through the authenticated official
  `gh` CLI and never reads or stores its token. Selected repository names are saved
  locally; removing a repository in Settings stops monitoring it.
- Downloads monitoring observes the selected local folder and can be disabled.
- Battery, Bluetooth, volume, brightness, and media state are read locally and kept
  in memory.
- When the brightness indicator is enabled, Pulse Notch listens for brightness-key
  events and reads the current brightness only after a key press. It does not store
  keystrokes. macOS may require Input Monitoring access to deliver these events
  while another app is focused; without it, the brightness indicator may not appear.
- Update checks query the public GitHub Releases API at most once per day and can be
  disabled in Settings.
- AI Agent (off by default):
  - Credentials for TypeSafe, OpenRouter, and optional local endpoints are stored in
    the macOS Keychain. **Disconnect** removes them.
  - With a hosted decision provider, each step sends the instruction, the step, and
    the names of the relevant on-screen controls. The decision provider never receives
    screenshots.
  - With a hosted language model, the conversation and a summary of the screen after
    each step are sent. Models that pass the vision check also receive a screenshot
    after each step.
  - Secure fields are never read, sent, typed into, or logged. Screen content is
    treated as task data, never as instructions that change permissions or rules.
  - Screenshots stay in memory and are discarded after use. Conversations, run
    summaries, goals, and routines are stored in a local SQLite database under
    `~/Library/Application Support/Pulse Notch/AIAgent`. History is kept for 30 days
    by default and can be cleared. Goals and routines are kept until you delete them.
  - Managed runtimes are downloaded only when you select Install. They run as child
    processes that listen only on loopback (`llama.cpp` requires a per-launch key)
    or on private pipes (Laya). They receive a minimal environment and none of Pulse
    Notch's desktop permissions. They stop when you disable the agent or quit.
  - Disabling the AI Agent cancels every run and stops managed processes. Deleting
    history and downloaded models is a separate, explicit action.
- Apart from the optional AI Agent keys, no credentials are stored by Pulse Notch.

Each integration can be disabled from Settings. macOS requests Calendar, Bluetooth,
or Downloads access only when the corresponding feature needs it. Accessibility and
Screen Recording are requested only when you turn on computer use for the AI Agent.

### Third-party runtimes and models

The optional managed components are pinned, with checksums, in
[`RuntimeManifest.json`](Sources/PulseNotchApp/Resources/AIAgent/RuntimeManifest.json):

| Component | Version | License |
|---|---|---|
| [python-build-standalone](https://github.com/astral-sh/python-build-standalone) CPython | 3.12.14+20260924 | PSF-2.0 |
| [laya-mlx](https://github.com/mizorewww/laya-mlx) and dependencies (hash-locked) | 0.2.0 | Apache-2.0 and others |
| [Laya Multilingual MLX](https://huggingface.co/aac6fef/laya-multilingual-mlx) (from `convaiinnovations/laya-multilingual`) | `f2b4faf` | Apache-2.0 |
| [llama.cpp](https://github.com/ggml-org/llama.cpp) server, Metal | b11146 | MIT |
| [MiMo-V2.6-Distill-Qwen-9B GGUF](https://huggingface.co/ggml-org/MiMo-V2.6-Distill-Qwen-9B-GGUF) Q8_0 and vision projector | `81baddc` | MIT |

These components are not bundled with Pulse Notch. They are downloaded from their
publishers only when you install them. The MiMo package needs about 10.2 GB of disk
space and at least 16 GB of memory. It uses its embedded, adapted chat template.

### AI Agent troubleshooting

- **"Pulse Notch needs Accessibility permission" on a build from source:** ad-hoc
  signatures change with every build, so macOS forgets the grant. Run
  `./Scripts/setup-computer-use.sh` once. It creates a local code-signing identity,
  rebuilds with it so later builds keep their permissions, clears stale entries, and
  opens System Settings, where you turn on Pulse Notch. macOS does not allow any
  script to grant this permission on your behalf.

- **"Not ready for computer use":** run **Test connection**. The model must return a
  structured tool call; text alone does not qualify. Choose a model that supports tools.
- **Screenshots unavailable:** the model did not pass the vision check, or Screen
  Recording is not granted. For a build from source, run
  `./Scripts/grant-screen-recording.sh`. It opens the right pane, waits for you to
  turn on Pulse Notch, and restarts the app, because macOS applies a new Screen
  Recording grant only after a restart.
- **Actions do nothing:** grant Accessibility in System Settings → Privacy & Security,
  and remove and re-add Pulse Notch if you updated the app.
- **"Insufficient context":** the local Laya model accepts 1,024 tokens. The task needs
  more than that. Simplify the window or instruction, or use JEV.
- **Run waits:** the Mac is locked, another desktop task holds control, or the agent
  composer is focused. Click elsewhere to release it.
- **Downloads fail or stall:** select **Retry**; downloads resume where they stopped.
  A checksum mismatch deletes the file. Check free disk space; the installer requires
  the download size plus 10%.
- **Local model does not start:** check free memory; MiMo Q8_0 needs 16 GB or more.
  Removing and reinstalling *llama.cpp* replaces the runtime without touching models.
- **Missed routines:** routines run only while Pulse Notch is open. Use **Run now**
  on the missed occurrence, or enable *Open at login*.

## Development

Settings use an AppKit window created by `SettingsWindowController` before its
SwiftUI content is installed. This lets the sidebar and detail backgrounds extend
behind the transparent titlebar; the menu bar item and ⌘, open that window.

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
