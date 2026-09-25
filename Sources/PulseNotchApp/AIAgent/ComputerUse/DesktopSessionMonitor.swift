import AppKit
import CoreGraphics
import PulseNotchCore

enum DesktopSessionEvent: Equatable, Sendable {
    case screenLocked
    case screenUnlocked
    case systemWillSleep
    case systemDidWake
    case displaysDidSleep
    case displaysDidWake
    case sessionDidResignActive
    case sessionDidBecomeActive
    case composerFocusChanged(Bool)
}

/// Whether the agent may send desktop input right now.
struct DesktopAvailabilityState: Equatable, Sendable {
    var locked = false
    var systemAsleep = false
    var displaysAsleep = false
    /// Another user is using the Mac through fast user switching.
    var sessionInactive = false
    var composerFocused = false

    var asleep: Bool { systemAsleep || displaysAsleep }
    var isAvailable: Bool { !locked && !asleep && !sessionInactive && !composerFocused }

    mutating func apply(_ event: DesktopSessionEvent) {
        switch event {
        case .screenLocked: locked = true
        case .screenUnlocked: locked = false
        case .systemWillSleep: systemAsleep = true
        case .systemDidWake:
            // A display wake notification is not guaranteed after system wake.
            systemAsleep = false
            displaysAsleep = false
        case .displaysDidSleep: displaysAsleep = true
        case .displaysDidWake: displaysAsleep = false
        case .sessionDidResignActive: sessionInactive = true
        case .sessionDidBecomeActive: sessionInactive = false
        case .composerFocusChanged(let focused): composerFocused = focused
        }
    }
}

/// Blocks agent input while the Mac is locked, asleep, switched to another user,
/// or while the user is typing in the agent's own composer.
final class DesktopSessionMonitor: DesktopAvailability, Sendable {
    private let coordinator: DesktopAvailabilityCoordinator
    private let events: AsyncStream<DesktopSessionEvent>.Continuation
    private let consumer: Task<Void, Never>
    private let observations: [NotificationObservation]

    /// Starts without observing system notifications; state changes only through `apply`.
    convenience init(initialState: DesktopAvailabilityState) {
        self.init(state: initialState) { _ in [] }
    }

    /// Observes lock, sleep, and session notifications for the lifetime of the monitor.
    @MainActor
    convenience init() {
        var state = DesktopAvailabilityState()
        state.locked = Self.isScreenLocked()
        self.init(state: state, observe: Self.systemObservations(sending:))
    }

    private init(
        state: DesktopAvailabilityState,
        observe: (AsyncStream<DesktopSessionEvent>.Continuation) -> [NotificationObservation]
    ) {
        let (stream, continuation) = AsyncStream.makeStream(of: DesktopSessionEvent.self)
        let coordinator = DesktopAvailabilityCoordinator(state: state)
        self.coordinator = coordinator
        events = continuation
        observations = observe(continuation)
        // A single consumer keeps events in delivery order, so a quick lock and
        // unlock cannot be applied in reverse.
        consumer = Task {
            for await event in stream {
                await coordinator.apply(event)
            }
        }
    }

    deinit {
        events.finish()
        consumer.cancel()
    }

    var isAvailable: Bool {
        get async { await coordinator.state.isAvailable }
    }

    var state: DesktopAvailabilityState {
        get async { await coordinator.state }
    }

    func waitUntilAvailable() async throws {
        try await coordinator.waitUntilAvailable()
    }

    /// Called by the composer UI; events are applied in the order they are sent.
    func setComposerFocused(_ focused: Bool) {
        events.yield(.composerFocusChanged(focused))
    }

    /// Emits the current availability, then every change.
    func availabilityUpdates() async -> AsyncStream<Bool> {
        await coordinator.availabilityUpdates()
    }

    /// Applies an event immediately, bypassing the ordered notification stream.
    func apply(_ event: DesktopSessionEvent) async {
        await coordinator.apply(event)
    }

    var pendingWaiterCount: Int {
        get async { await coordinator.pendingWaiterCount }
    }

    private static func isScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    private static func systemObservations(
        sending events: AsyncStream<DesktopSessionEvent>.Continuation
    ) -> [NotificationObservation] {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        let mapping: [(NotificationCenter, Notification.Name, DesktopSessionEvent)] = [
            (distributed, Notification.Name("com.apple.screenIsLocked"), .screenLocked),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), .screenUnlocked),
            (workspace, NSWorkspace.willSleepNotification, .systemWillSleep),
            (workspace, NSWorkspace.didWakeNotification, .systemDidWake),
            (workspace, NSWorkspace.screensDidSleepNotification, .displaysDidSleep),
            (workspace, NSWorkspace.screensDidWakeNotification, .displaysDidWake),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, .sessionDidResignActive),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionDidBecomeActive)
        ]
        return mapping.map { center, name, event in
            NotificationObservation(center: center, name: name) { _ in events.yield(event) }
        }
    }
}

actor DesktopAvailabilityCoordinator {
    private(set) var state: DesktopAvailabilityState
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var listeners: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init(state: DesktopAvailabilityState) {
        self.state = state
    }

    var pendingWaiterCount: Int { waiters.count }

    func apply(_ event: DesktopSessionEvent) {
        let wasAvailable = state.isAvailable
        state.apply(event)
        guard state.isAvailable != wasAvailable else { return }
        listeners.values.forEach { $0.yield(state.isAvailable) }
        guard state.isAvailable else { return }
        let resumed = waiters.values
        waiters.removeAll()
        resumed.forEach { $0.resume() }
    }

    func waitUntilAvailable() async throws {
        try Task.checkCancellation()
        // Availability can flip back before a resumed waiter runs, so re-check each time.
        while !state.isAvailable {
            let id = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        waiters[id] = continuation
                    }
                }
            } onCancel: {
                Task { await self.cancelWaiter(id) }
            }
            try Task.checkCancellation()
        }
    }

    func availabilityUpdates() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
        let id = UUID()
        listeners[id] = continuation
        continuation.yield(state.isAvailable)
        continuation.onTermination = { _ in
            Task { await self.removeListener(id) }
        }
        return stream
    }

    private func cancelWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func removeListener(_ id: UUID) {
        listeners.removeValue(forKey: id)
    }
}
