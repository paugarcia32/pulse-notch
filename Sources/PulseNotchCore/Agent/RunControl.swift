import Foundation

public protocol AgentClock: Sendable {
    var now: Date { get }
}

public struct SystemAgentClock: AgentClock {
    public init() {}
    public var now: Date { Date() }
}

/// Reports whether the agent may send desktop input: the Mac must be awake and
/// unlocked, and the agent's own composer must not be focused.
public protocol DesktopAvailability: Sendable {
    /// Suspends until desktop input is allowed. Throws when the task is cancelled.
    func waitUntilAvailable() async throws
}

public struct AlwaysAvailableDesktop: DesktopAvailability {
    public init() {}
    public func waitUntilAvailable() async throws { try Task.checkCancellation() }
}

/// Grants exclusive desktop control to one run at a time. Other runs wait in FIFO order.
public actor DesktopLease {
    private var holder: UUID?
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    public init() {}

    public var currentHolder: UUID? { holder }
    public var queuedRunIDs: [UUID] { waiters.map(\.id) }

    /// Returns immediately when the run already holds the lease.
    /// - Parameter onQueued: Called once when the run has to wait.
    public func acquire(for runID: UUID, onQueued: @Sendable () -> Void = {}) async throws {
        try Task.checkCancellation()
        if holder == nil { holder = runID; return }
        if holder == runID { return }
        onQueued()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append((runID, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(runID) }
        }
    }

    public func release(_ runID: UUID) {
        guard holder == runID else {
            cancelWaiter(runID)
            return
        }
        if waiters.isEmpty {
            holder = nil
        } else {
            let next = waiters.removeFirst()
            holder = next.id
            next.continuation.resume()
        }
    }

    private func cancelWaiter(_ runID: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == runID }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

/// Pause, resume, stop, and approval signalling for one run.
public actor RunControl {
    public enum State: Sendable, Equatable {
        case active
        case paused
        case stopped
    }

    public private(set) var state: State = .active
    private var resumeWaiters: [CheckedContinuation<Void, Error>] = []
    private var approval: CheckedContinuation<Bool, Never>?

    public init() {}

    public func pause() {
        guard state == .active else { return }
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        state = .active
        resumeWaiters.forEach { $0.resume() }
        resumeWaiters.removeAll()
    }

    /// Prevents any further actions. It cannot undo completed actions.
    public func stop() {
        state = .stopped
        resumeWaiters.forEach { $0.resume(throwing: CancellationError()) }
        resumeWaiters.removeAll()
        approval?.resume(returning: false)
        approval = nil
    }

    /// Suspends while paused and throws once the run is stopped or cancelled.
    /// - Returns: Whether the run had to wait.
    @discardableResult
    public func checkpoint() async throws -> Bool {
        try Task.checkCancellation()
        switch state {
        case .stopped: throw CancellationError()
        case .active: return false
        case .paused:
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        resumeWaiters.append(continuation)
                    }
                }
            } onCancel: {
                Task { await self.stop() }
            }
            try Task.checkCancellation()
            return true
        }
    }

    /// Waits for the user's answer in supervised mode.
    public func requestApproval() async -> Bool {
        guard state != .stopped else { return false }
        approval?.resume(returning: false)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume(returning: false) } else { approval = continuation }
            }
        } onCancel: {
            Task { await self.answerApproval(false) }
        }
    }

    public var isAwaitingApproval: Bool { approval != nil }

    public func answerApproval(_ approved: Bool) {
        approval?.resume(returning: approved)
        approval = nil
    }
}
