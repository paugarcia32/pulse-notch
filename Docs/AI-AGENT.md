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

## Execution loop: the language model directs, JEV or Laya operates

The language model (OpenRouter or local) is the director. It never picks on-screen
controls itself. Instead it breaks the task into natural-language steps and calls
`operate(step:text:)` for each one, for example "click the Save button" or "type the
text into the document body" with `text: "ciao"`. It can also call `open_app`,
`open_url`, `observe_screen`, and, for vision-capable models, `capture_screen`.

Within each step, JEV or Laya is the operator:

1. Pulse Notch takes a fresh Accessibility observation and builds the candidate
   actions.
   - There is one candidate per relevant control: click, or type into text inputs.
   - Generic actions are always available: type at the cursor, Return, Tab, Escape,
     and scroll.
   - Two outcome options are always available: "the step is already done on screen"
     and "none of these actions helps".
   - Option names are descriptive, because Laya weighs option names more than their
     descriptions.
2. The decision provider picks the next action with a `choice` question.
   - "Done" requires at least 50% confidence.
   - Any other choice requires at least 20%.
3. Some actions are potentially sensitive: controls labelled Delete, Send, Buy, Quit,
   Allow, and similar, plus Return and modifier shortcuts. For these, a `noul` question
   asks about unrequested side effects. A likely side effect moves the run to Needs
   input.
4. The rest of the pipeline follows:
   - the executor validates the target;
   - in supervised mode, the user approves the action;
   - the action is executed and a new observation is taken;
   - a `score` question verifies the effect.
5. The loop repeats until the decision provider chooses "done". A step is limited to
   eight actions, and a repeated action ends it.
6. The step result returns to the language model. With a model that passed the vision
   check, the result includes an ephemeral screenshot. The model confirms the work is
   on track, corrects course with another step, or asks the user for help.

Goals finish only after a `score` question confirms that the observed state satisfies
the completion criteria. The evidence is stored with the run.

Failure handling:

- Recoverable failures are abstentions, stale targets, failed checks, and typing
  steps that arrive without text. After `maximumReplans` of them (default two), the
  run pauses with an explanation.
- Reaching the action or time limit moves the run to Needs input.
- Provider errors fail the run. The runner never switches providers.

Decision state is fitted to the provider's context limit: 1,024 tokens for Laya
Multilingual, and 32k for JEV's state plus the longest question.

- Candidate controls are ranked by relevance to the step.
- The generic and outcome options are always kept.
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
| MiMo directing Laya on a simulated TextEdit window ("write the word ciao") | Completed in 15 s. MiMo recovered from a missing `text` argument; Laya chose to type (45%), then "done" (55%); MiMo checked the screenshot and finished with evidence. |

Some checks still need a person: hosted providers with real keys, computer use with
Accessibility granted, VoiceOver, multiple displays, and macOS 14. They are listed in
the pull request's manual acceptance checklist.
