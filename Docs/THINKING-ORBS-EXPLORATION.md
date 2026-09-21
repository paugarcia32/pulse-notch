# Thinking Orbs exploration

Status: exploration complete  
Date: 2026-09-21  
Implementation status: no product changes made

## Summary

[HAPLO ThinkingOrbs](https://github.com/haplollc/ThinkingOrbs) is a strong
technical and visual foundation for animated activity glyphs in Pulse Notch.
It is already a native SwiftUI package compatible with the app's Swift 6 and
macOS 14 baseline.

The recommended direction is to use this visual language selectively for live
activity and transitions. It should not replace SF Symbols, numeric progress,
timestamps, or explicit success and failure states.

Creating Pulse-specific designs is feasible, but requires a fork: the package
exposes rendered frames for its existing designs, while its design registry,
presets, and geometry engine are internal.

## Sources reviewed

- [HAPLO ThinkingOrbs](https://github.com/haplollc/ThinkingOrbs), version 1.1.0,
  commit `e2c07bbdec4db797fb302300ef0159b1806a909f`.
- [Original thinking-orbs project](https://github.com/Jakubantalik/thinking-orbs).
- The HAPLO source, tests, generated media, package manifest, and license.
- The current Pulse Notch activity models, collapsed indicators, agent page,
  surface behavior, and attached screen recording.

## What the package provides

- Swift 6 and macOS 14 support.
- Native SwiftUI rendering with one `Canvas` inside one `TimelineView`.
- Nine hand-tuned animated designs at 64 pt and 20 pt.
- Deterministic geometry: each frame is a draw list of points and lines.
- No runtime dependencies, shaders, Metal, filters, or image assets.
- A shared clock so multiple visible animations stay in phase.
- Automatic pause when offscreen or when the app is in the background.
- Reduce Motion, Increase Contrast, and VoiceOver behavior.
- Golden-vector, rendering, accessibility, and public API tests.
- MIT licensing.

The production implementation is approximately 1,450 lines. Roughly 900 of
those lines are the geometry engine and presets; the rest is SwiftUI rendering,
labels, and the public frame API.

## Animation versus interaction

The movement shown in the recording is animation rather than direct pointer
interaction.

The current package supports changing design, speed, pause state, theme, and a
deterministic clock. It does not implement hover distortion, cursor attraction
or repulsion, dragging, or automatic geometric transitions between designs.
Its recommended transition between states is a crossfade.

Pulse Notch should initially preserve that behavior. Hover already has a clear
product meaning—opening or keeping the notch surface open—and a second reactive
effect could make the surface feel nervous. Pointer-driven distortion can be
reconsidered only after the passive animations have been tested in context.

## Fit with the current Pulse model

| Existing design | Fit | Honest use in Pulse today |
| --- | --- | --- |
| `working` | Excellent | A coding agent is running. |
| `connecting` | Good | A connection, synchronization, or tool call, if that state is known. |
| `searching` | Future | Only when an integration can report a real search phase. |
| `solving` | Future | Only when an agent can report reasoning or code execution. |
| `composing` | Future | Only when an agent can report response generation. |
| `weaving` | Weak today | Possible future multi-agent planning state. |
| `listening` | Weak | Visually resembles audio, but listening is not playback. |
| `breathing` | Weak | A permanently animated idle state would add ambient noise. |
| `shaping` | Weak today | Possible future visual or layout generation state. |

Pulse currently knows whether a coding-agent session is running or completed;
it does not know whether the agent is searching, solving, connecting, or
composing. Mapping those designs now would communicate information the product
does not possess. `working` is the only accurate current agent mapping.

The existing `AgentActivityOrbit` is a natural first candidate for comparison
with `working`, especially in expanded agent rows. It should not be replaced
without testing the collapsed surface separately.

## Pulse-specific designs worth exploring

### Pipeline

For a running GitHub Actions workflow. Branching paths or connected nodes carry
a pulse toward a destination. Completion and failure should continue to use
clear static symbols rather than attempting to encode every result in motion.

### Transfer

For active downloads. Particles descend and collect inside an arc or container.
The animation shows activity; the existing percentage remains visible for
precision.

### Countdown

For calendar events and timers. A dotted ring uses a sweep or progressively
changes its occupied arc. It complements, rather than replaces, values such as
`31m` or `04:32`.

### Playback pulse

A lower-priority design for active media. A point waveform travels along a line
or ring. It should be designed as playback, rather than reusing the semantically
different `listening` animation.

No new agent glyph is needed initially because `working` already covers that
state well.

## Recommended ownership model

Using only the existing designs would require no fork; Pulse could depend on
the upstream package directly.

Custom designs require one of the following:

1. Maintain a small fork with new enum cases, geometry builders, and presets.
2. Propose an extensibility API upstream and build on it if accepted.
3. Reimplement the relevant engine inside Pulse.

A small fork is the most direct option. Reimplementing the engine would create
more code to own, while waiting for a generalized upstream extension point is
unnecessary for a product-specific experiment.

The fork should retain upstream attribution and stay structurally close to
HAPLO so fixes can be reviewed and merged manually. A possible product name is
`PulseOrbs`, but naming is a separate decision from the technical spike.

## Required adaptations

### A notch-specific size

ThinkingOrbs provides independently tuned 64 pt and 20 pt variants. Pulse's
collapsed activity indicators are approximately 14 pt. Scaling the 20 pt preset
down is likely to make dots too small or visually muddy.

The fork should therefore add a separately tuned 14–16 pt notch preset with
fewer, larger dots. The exact diameter must come from visual testing on both a
physical notch and the external-display capsule.

### Optional tint

ThinkingOrbs is intentionally monochrome. Pulse currently uses category colors
and lets users customize several indicator colors. The fork should explore an
optional tint while preserving depth through dot radius and opacity.

Monochrome white remains a valid fallback on the black notch surface. Color
must never become the only indication of state.

### Product-level animation limits

The package can animate many orbs, but Pulse should impose a calmer product
policy:

- Animate only ongoing activity.
- Prefer static, explicit symbols for completion and failure.
- Keep numeric progress and countdown values.
- Limit simultaneous motion in the collapsed notch.
- Pause hidden pages and inactive indicators.
- Render a meaningful static frame with Reduce Motion.

## Architecture fit

The package belongs entirely in `PulseNotchApp`. Domain models should continue
to expose factual states such as running, completed, failed, and percentage.
The presentation layer maps those facts to a particle design.

This preserves the repository dependency direction:

```text
Views -> feature state/use cases -> domain <- integration adapters
```

No orb type, SwiftUI type, animation phase, or color should enter
`PulseNotchCore`.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Dots are illegible at collapsed-notch size. | Create and validate a dedicated 14–16 pt preset. |
| Too many animations make the notch distracting. | Animate only live work and cap simultaneous motion. |
| A design implies a state Pulse cannot observe. | Map only factual domain states. |
| Animation replaces useful information. | Preserve numbers, labels, and terminal-state symbols. |
| Tint weakens the original depth treatment. | Prototype monochrome and tinted variants side by side. |
| The fork drifts from upstream. | Keep changes narrow, record the upstream base, and review updates deliberately. |
| Continuous rendering affects power use. | Measure collapsed and expanded cases; pause invisible work. |

## Licensing

The HAPLO port and original designs are MIT licensed. A fork may be used,
modified, and distributed with Pulse Notch, including commercially, provided
the copyright and permission notices remain in copies or substantial portions
of the software.

The fork and any redistributed source or notices must retain attribution to
both HAPLO LLC and Jakub Antalik as present in the upstream license.

## Verification performed during exploration

- Inspected the package source, API, geometry engine, presets, tests, media, and
  license.
- Confirmed the current Pulse package and HAPLO package both target macOS 14 and
  Swift 6.
- Confirmed the current Pulse agent model exposes only running and completed
  states.
- Confirmed the package contains no hover, pointer, or drag interaction.
- Attempted `swift test` against HAPLO version 1.1.0.

The test attempt could not complete because the development environment had
`/Library/Developer/CommandLineTools` selected instead of a full Xcode
installation. The SwiftUI `@Entry` and `#Preview` macro plugins were therefore
unavailable. This is an environment limitation, not evidence of a package
failure. A future spike must build and test with the project's supported Xcode
toolchain.

## Decision

Proceed to a visual and technical spike when this work is prioritized, using
`working` plus a dedicated notch-size preset as the first proof. Do not adopt
all nine designs or implement custom designs until that spike shows that the
visual language remains calm and legible in the real collapsed and expanded
surfaces.

