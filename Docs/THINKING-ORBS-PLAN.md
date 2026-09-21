# Thinking Orbs adoption plan

Status: in progress — Phase 1 complete  
Related research: [THINKING-ORBS-EXPLORATION.md](THINKING-ORBS-EXPLORATION.md)

## Goal

Determine whether dotted, animated activity glyphs improve Pulse Notch, then
adopt the smallest useful set without reducing clarity, accessibility, or the
calm character of the product.

## Non-goals

- Replacing every Pulse icon.
- Recreating all nine upstream designs.
- Inferring detailed agent phases from a running process.
- Adding pointer distortion, drag behavior, or decorative idle animation.
- Moving animation concepts into `PulseNotchCore`.

## Decisions to make before implementation

- [x] Confirm that a public fork is acceptable and choose its repository and
      package name.
- [x] Confirm whether the first spike may add a temporary local package
      dependency or should live only in the fork's demo gallery.
- [x] Select a full Xcode installation for build and test verification.
- [x] Choose the maximum number of simultaneous collapsed-notch animations to
      evaluate; start with one.

## Phase 1: establish the fork

Create the smallest maintainable fork of HAPLO ThinkingOrbs.

Tasks:

- [x] Fork from version 1.1.0 or a newly reviewed upstream release.
- [x] Preserve the upstream MIT license and both copyright notices.
- [x] Record the upstream repository, tag, and commit in the fork README.
- [x] Confirm the unmodified fork builds and its tests pass with the supported
      Xcode toolchain.
- [x] Avoid renaming public API until the spike proves that Pulse will adopt it.

Exit criteria:

- The unmodified baseline builds and tests successfully.
- Attribution and upstream provenance are explicit.
- There are no unrelated changes in the fork.

## Phase 2: notch-size feasibility spike

Prove the visual language at the actual collapsed-notch scale before designing
new glyphs.

Tasks:

- [x] Add an independently tuned 20 pt Pulse agent design.
- [x] Select the final display size after comparing it at 16, 18, and 20 pt.
- [x] Preserve the upstream `working` design and its public API unchanged.
- [x] Compare it with the current `AgentActivityOrbit` in an isolated gallery.
- [ ] Evaluate monochrome white and the existing agent tint.
- [ ] Capture Reduce Motion and Increase Contrast variants.
- [ ] Measure frame cost and idle CPU use with one and several visible glyphs.

Evaluate in:

- A physical MacBook notch.
- The external-display capsule.
- Collapsed and expanded Pulse surfaces.
- Light and dark desktop backgrounds behind any translucent expanded content.
- Standard and increased display scaling.

Exit criteria:

- The glyph remains recognizable without shimmering or muddy subpixel dots.
- It does not change the collapsed notch's hit testing or hover behavior.
- Reduce Motion presents a meaningful static state.
- CPU and energy impact are acceptable for an ambient menu-bar utility.
- A side-by-side review prefers it to the current orbit.

Stop if these criteria cannot be met without increasing the collapsed surface
or making the dots visually heavy.

## Phase 3: define the Pulse visual grammar

Document a small set of rules before adding product-specific designs.

Tasks:

- [ ] Fix the supported sizes and dot-density ranges.
- [ ] Decide how optional tint maps depth to radius, opacity, and luminance.
- [ ] Define motion ranges for calm, active, and urgent states.
- [ ] Define how designs enter, leave, and crossfade.
- [ ] Define the collapsed animation limit and selection priority.
- [ ] Record static fallbacks for Reduce Motion.

Exit criteria:

- A new design can be reviewed against written visual and accessibility rules.
- Motion communicates activity rather than category or decoration.
- Color is supplementary and never the sole state signal.

## Phase 4: prototype Pulse-specific designs

Build designs one at a time in a standalone gallery, in this order:

1. `pipeline` for running GitHub Actions.
2. `transfer` for active downloads.
3. `countdown` for calendar events and timers.
4. `playbackPulse` only if the first three succeed and media still benefits.

For each design:

- [ ] Write a one-sentence semantic contract.
- [ ] Implement regular, small, and notch presets only where the product uses
      them.
- [ ] Add deterministic frame tests at representative timestamps.
- [ ] Add light, dark, tinted, and reduced-motion reference renders.
- [ ] Test at actual size rather than reviewing only enlarged media.
- [ ] Reject it if existing native controls communicate the state more clearly.

Do not add another agent design during this phase; use the Pulse-specific agent
glyph established by the Phase 2 spike.

Exit criteria per design:

- A user can distinguish its activity from the other accepted designs at the
  intended size.
- It does not pretend to show progress that the model cannot provide.
- Its static fallback remains understandable.
- It has deterministic geometry coverage.

## Phase 5: integrate one vertical slice

Integrate only the strongest proven design first. The default candidate is the
Pulse-specific agent activity glyph for active coding-agent rows and the
corresponding collapsed agent indicator.

Tasks:

- [ ] Add the fork as a version- or revision-pinned Swift Package dependency.
- [ ] Keep the model-to-design mapping in `PulseNotchApp`.
- [ ] Preserve the existing completed-agent checkmark.
- [ ] Preserve VoiceOver labels describing the factual activity.
- [ ] Preserve user-configurable category color where the chosen tint treatment
      supports it.
- [ ] Add or update focused presentation tests.
- [ ] Verify opening, closing, swiping, and hover expansion remain interruptible.

Exit criteria:

- Existing domain and integration APIs remain unchanged.
- Running and completed states are immediately distinguishable without color.
- No regression appears in notch sizing, hover behavior, page navigation, or
  accessibility.
- Relevant tests and the full practical test suite pass without new warnings.

## Phase 6: decide adoption scope

Review the first integrated slice in normal daily use before adding more motion.

- [ ] Keep or revert the agent glyph based on the real in-context result.
- [ ] If kept, integrate accepted custom designs individually in priority order.
- [ ] Reassess the simultaneous-animation limit with real activity combinations.
- [ ] Document rejected designs and why they were rejected.
- [ ] Tag a stable fork release only after Pulse consumes it successfully.

## Candidate state mapping

| Pulse state | Animated design | Static or precise companion |
| --- | --- | --- |
| Coding agent running | `PulseAgentActivityOrb` | Agent identity and session text |
| Coding agent completed | None | Checkmark |
| GitHub Actions running | `pipeline` | Workflow/repository text |
| GitHub Actions succeeded | None | Checkmark |
| GitHub Actions failed | None | Failure symbol |
| Download active | `transfer` | Percentage or indeterminate marker |
| Calendar approaching | `countdown` | Minutes until start |
| Timer running | `countdown` | Exact elapsed/remaining time |
| Media playing | `playbackPulse`, optional | Track metadata and playback controls |

## Validation checklist

- [x] `swift test` passes for the fork.
- [ ] `swift test` passes for Pulse Notch.
- [ ] Relevant Xcode build and test scheme passes when available.
- [ ] No new warnings.
- [ ] Collapsed and expanded surfaces are checked manually.
- [ ] Physical notch and external-display capsule are checked.
- [ ] Reduce Motion, Increase Contrast, VoiceOver, and keyboard behavior are
      checked.
- [ ] Multiple active integrations do not create excessive motion.
- [ ] CPU and energy impact are measured rather than inferred.
- [ ] License and attribution are present in distributed artifacts.

## Next action

Review the final 20 pt `PulseAgentActivityOrb` beside the current
`AgentActivityOrbit` in the fork's demo gallery. Check both white and the
default cyan agent tint. That comparison is the go/no-go gate for everything
else in this plan.
