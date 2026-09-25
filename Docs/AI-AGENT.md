# AI Agent architecture

The AI Agent is an optional page, off by default. It adds chat, computer use, goals,
and routines to the notch. It runs entirely in Swift inside Pulse Notch and needs no
external agent installation.

## Layers

| Layer | Location | Responsibility |
|---|---|---|
| Domain | `Sources/PulseNotchCore/Agent` | Configuration, typed decisions, language-model streaming, observations and actions, context budgeting, run state, goals, routines, and scheduling. No SwiftUI or AppKit. |
| Execution | `AgentRunner` (actor) | The loop: instruction, observe, plan, decide, validate, execute, observe again, verify. |
| Providers | `Sources/PulseNotchApp/AIAgent/Providers` | System One (JEV, Laya services), managed Laya helper, OpenAI-compatible streaming (OpenRouter, llama.cpp), and capability probes. |
| Runtime | `…/AIAgent/Runtime` | Pinned manifest, resumable and verified downloads, installs, GGUF import, and the managed `llama.cpp` and Laya processes. |
| Computer use | `…/AIAgent/ComputerUse` | Accessibility observation, target validation, input synthesis, ScreenCaptureKit screenshots, permissions, and lock/sleep monitoring. |
| Persistence | `…/AIAgent/Persistence` | Versioned SQLite store for conversations, goals, routines, runs, and occurrences. |
| Feature and UI | `…/AIAgent/Feature`, `…/AIAgent/UI` | `@MainActor` model that owns run tasks and the scheduler, plus the SwiftUI page. |

## Execution loop

1. The language model receives the conversation and the tool definitions.
   - Desktop tools are offered only when computer use is on and the model passed a
     tool-call probe.
   - `capture_screen` is offered only when the model also passed a vision probe.
2. Each desktop tool call runs through these steps:
   1. The run acquires the exclusive desktop lease; other runs wait in a queue.
   2. The run waits until the Mac is unlocked and awake, and the composer is not focused.
   3. It checks application restrictions.
   4. It takes a fresh observation and re-anchors the target: elements by role and
      label, coordinates only within the same window.
   5. The executor validates the action against that observation.
   6. The decision provider answers typed questions. These are `noul` (is the
      action aligned with the instruction and free of unrequested side effects?) and
      `choice` (which listed control, if any, is the right target?).
      - A high-confidence choice can correct the target.
      - Low alignment moves the run to Needs input.
   7. In supervised mode, the user approves the action.
   8. The action is executed.
   9. A new observation is taken.
   10. A `score` question verifies the outcome.
3. Goals finish only after a `score` question confirms that the observed state
   satisfies the completion criteria. The evidence is stored with the run.
4. Failure handling:
   - Recoverable failures are stale targets, missing controls, and failed checks. After
     `maximumReplans` of them (default two), the run pauses with an explanation.
   - Reaching the action or time limit moves the run to Needs input.
   - Provider errors fail the run. The runner never switches providers.

Decision state is fitted to the provider's context limit: 1,024 tokens for Laya
Multilingual, and 32k for JEV's state plus the longest question.

- Controls are ranked by relevance to the instruction.
- The proposed target is always kept.
- Secure fields are dropped.
- If the decisive information does not fit, the run reports insufficient context
  instead of truncating it.

## Managed runtimes

- **Laya**
  - Runs `laya_helper.py` in a python-build-standalone virtual environment.
  - `laya-mlx` and its dependencies are installed with `pip --require-hashes` from a
    committed lock file.
  - The helper exchanges versioned newline-delimited JSON over stdin and stdout.
  - It runs with `HF_HUB_OFFLINE=1` and loads the checkpoint from disk.
- **llama.cpp**
  - `llama-server` listens on `127.0.0.1` on a free port.
  - It uses `--jinja`, which keeps the model's embedded template, and a per-launch
    key file readable only by the user.
- Both processes receive a minimal environment. They stop when the agent is disabled
  and before Pulse Notch quits.

## Verified matrix

The following were measured on 25 September 2026 on an Apple Silicon Mac running
macOS 26.6.2, using the pinned manifest. Each check drove the production classes
directly.

| Check | Result |
|---|---|
| Python runtime and hash-locked `laya-mlx` install | Passed (21 s) |
| Laya Multilingual download (678 MB) and checksum verification | Passed (59 s) |
| Laya helper start | 2.8 s |
| Laya typed decisions through the helper (choice, noul, score in one request) | 951 ms first request, then 20–32 ms. Chose the correct target at 0.91 confidence. |
| llama.cpp b11146 download and extraction | Passed |
| MiMo Q8_0 and mmproj download (10.15 GB) and checksum verification | Passed (458 s at about 22 MB/s) |
| `llama-server` load to healthy | 25 s |
| MiMo structured tool call (capability probe) | Passed |
| MiMo image interpretation (capability probe) | Passed |
| MiMo agent turn with the real tool schema ("Open TextEdit.") | `open_app {"name": "TextEdit"}` in 3 s |
| Unauthenticated request to the managed server | Rejected (401) |

Some checks still need a person: hosted providers with real keys, computer use with
Accessibility granted, VoiceOver, multiple displays, and macOS 14. They are listed in
the pull request's manual acceptance checklist.
