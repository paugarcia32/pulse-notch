# Pulse Notch Engineering Guide

## Product

Pulse Notch is a native macOS app that turns the area around the display notch into
an ambient, expandable activity surface.

The product will eventually aggregate:

- Upcoming calendar events and reminders.
- GitHub activity such as Actions, runners, pull requests, and reviews.
- Coding-agent status from tools such as Codex and Claude Code.
- Now-playing controls for music and video.
- Other small, time-sensitive signals that benefit from being visible but quiet.

The notch is not a notification center replacement. It should surface a small
number of relevant items, remain unobtrusive, and expand only when useful.

## Priorities

When requirements compete, use this order:

1. User privacy and system safety.
2. Native macOS behavior and accessibility.
3. Correctness and reliability.
4. A calm, responsive interface.
5. Maintainability and testability.
6. Feature breadth.

## Technology

- Swift 6 or newer.
- SwiftUI for declarative UI.
- AppKit where macOS window, panel, display, media, or system integration requires
  it.
- Swift Package Manager for packages and dependency management.
- Swift Testing for unit and integration tests.
- Structured concurrency (`async`/`await`, actors, and task groups).

Prefer Apple frameworks over third-party dependencies. Add a dependency only when
it removes substantial complexity and has a clear maintenance, privacy, and
licensing story.

## Architecture

Organize code by responsibility and feature, not by UI type.

- `PulseNotchCore`: platform-independent domain models and behavior.
- `PulseNotchApp`: macOS app composition, SwiftUI views, AppKit adapters, and
  system integrations.
- Future integrations should live behind small protocols and expose normalized
  domain events to the core.

Dependencies point inward:

```text
Views -> Feature state/use cases -> Domain <- Integration adapters
```

Rules:

- Domain code must not import SwiftUI or AppKit.
- Views render state and send user intent; they do not perform network, file, or
  credential operations.
- External services are accessed through protocols.
- App composition owns concrete implementations and dependency wiring.
- Prefer value types and explicit state transitions.
- Avoid global mutable state and shared singletons.
- Do not introduce a generic abstraction until at least two real use cases need
  it.

For a new feature, prefer a vertical slice containing its model, use case,
adapter, UI, and tests rather than scattering unrelated files across broad
folders.

## Code Quality

- Write small types with one clear responsibility.
- Use names that describe product behavior, not implementation accidents.
- Keep functions focused; extract behavior when a name improves understanding.
- Prefer immutable values. Restrict mutation to the narrowest scope.
- Model invalid states out of existence when practical.
- Handle errors explicitly. Never silently discard an error that affects the
  user or data integrity.
- Avoid force unwraps, force casts, `try!`, and `fatalError` outside of truly
  unrecoverable programmer errors.
- Do not leave commented-out code, placeholder branches, or unexplained TODOs.
  A TODO must include why it exists and the condition for removing it.
- Comments explain intent, constraints, or surprising system behavior. Do not
  narrate straightforward code.
- Keep public API surface minimal.
- Follow the existing local style. Do not reformat unrelated files.

## Swift and Concurrency

- Enable and respect strict concurrency checking.
- UI state and AppKit objects belong on `@MainActor`.
- Long-running work must not execute on the main actor.
- Prefer `Sendable` values crossing isolation boundaries.
- Use actors for genuinely shared mutable state.
- Preserve task cancellation and check it in long-running operations.
- Give unstructured tasks a clear owner and lifetime.
- Avoid detached tasks unless actor inheritance is specifically undesirable and
  documented.

## UI and macOS Behavior

- Build a macOS app, not an iOS interface enlarged for desktop.
- The collapsed surface must not steal focus or block nearby menu-bar controls.
- Support multiple displays, displays without a notch, Spaces, full-screen apps,
  and display configuration changes.
- Motion must respect Reduce Motion.
- Content must remain usable with VoiceOver, keyboard navigation, increased
  contrast, and reduced transparency.
- Avoid relying on color alone to communicate state.
- Use system materials, typography, symbols, and controls unless a custom
  treatment has a product reason.
- Keep animation interruptible and state-driven.
- Treat screen geometry as runtime input; never hard-code a specific Mac model's
  notch dimensions.

## Privacy and Security

- Request the minimum macOS permissions needed, at the moment they become useful.
- Keep credentials in Keychain. Never store tokens in source, `UserDefaults`,
  logs, fixtures, or screenshots.
- Prefer local processing and least-privilege API scopes.
- Redact personal data, repository secrets, URLs with tokens, and media metadata
  from logs.
- Every integration must define its permission needs, data retention, refresh
  behavior, error behavior, and disconnect path.
- No telemetry is added without an explicit product decision and documentation.

## Testing

Every behavior change needs proportionate automated coverage.

- Unit-test domain rules, ordering, filtering, state transitions, and error
  handling.
- Test integration adapters with deterministic fakes or recorded fixtures that
  contain no secrets.
- Add UI tests only for critical end-to-end flows that unit tests cannot cover.
- Tests must be deterministic: no real network, wall-clock assumptions, random
  sleeps, or dependence on the developer's machine state.
- Inject clocks, identifiers, clients, and persistence when behavior depends on
  them.
- A bug fix should include a regression test that fails before the fix.
- Name tests by behavior and outcome.

Run the test suite with:

```sh
swift test
```

When an Xcode project is introduced, also run its relevant build and test scheme.

## Working Agreement

Before changing code:

1. Read the nearby implementation and tests.
2. Check the working tree and preserve unrelated user changes.
3. Identify the smallest coherent change that satisfies the request.

While changing code:

1. Keep production code and tests in the same change.
2. Avoid speculative infrastructure and unrelated cleanup.
3. Update documentation when behavior, architecture, setup, or permissions change.
4. Never commit generated build output, credentials, signing assets, or
   user-specific Xcode state.

Before considering work complete:

1. Build the affected targets.
2. Run relevant tests, then the full test suite when practical.
3. Review the diff for accidental changes, secrets, debug output, and dead code.
4. Verify important UI changes manually, including collapsed and expanded states.
5. Report what changed, what was verified, and any remaining risk.

## Definition of Done

A change is done when:

- The requested behavior works.
- The design respects the dependency direction above.
- Relevant tests exist and pass.
- Accessibility, privacy, and failure states were considered.
- There are no new warnings.
- Documentation is current.
- The diff contains only intentional changes.
