import Foundation

public enum RunTrigger: Codable, Hashable, Sendable {
    case chat(conversationID: UUID)
    case goal(goalID: UUID)
    case routine(routineID: UUID, occurrence: OccurrenceKey?)
}

public enum NeedsInputReason: Codable, Hashable, Sendable {
    case approval(actionSummary: String)
    case question(String)
    case unauthorizedApplication(String)
    case unresolvedIntent(String)
    case invalidTarget(String)
    case insufficientContext(String)
    case limitReached(String)
    case permissionMissing(String)

    public var message: String {
        switch self {
        case .approval(let summary): "Approve the next action: \(summary)"
        case .question(let question): question
        case .unauthorizedApplication(let app): "The agent is not allowed to control \(app)."
        case .unresolvedIntent(let detail): "The agent is not sure what to do next: \(detail)"
        case .invalidTarget(let detail): "The target could not be used: \(detail)"
        case .insufficientContext(let detail): detail
        case .limitReached(let detail): detail
        case .permissionMissing(let detail): detail
        }
    }
}

public enum RunStatus: Codable, Hashable, Sendable {
    case queued
    case running
    case paused(reason: String?)
    case needsInput(NeedsInputReason)
    case completed(evidence: String)
    case failed(message: String)
    case stopped
    /// The app quit or crashed during the run; the outcome of the last action is uncertain.
    case interrupted

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .stopped, .interrupted: true
        case .queued, .running, .paused, .needsInput: false
        }
    }

    public var label: String {
        switch self {
        case .queued: "Queued"
        case .running: "Running"
        case .paused: "Paused"
        case .needsInput: "Needs input"
        case .completed: "Completed"
        case .failed: "Failed"
        case .stopped: "Stopped"
        case .interrupted: "Interrupted"
        }
    }

    /// Whether moving to `next` is a legal transition.
    public func canTransition(to next: RunStatus) -> Bool {
        if isTerminal { return false }
        switch (self, next) {
        case (_, .stopped), (_, .failed), (_, .interrupted): return true
        case (.queued, .running): return true
        case (.running, .paused), (.running, .needsInput), (.running, .completed), (.running, .queued): return true
        case (.paused, .running), (.needsInput, .running): return true
        case (.paused, .needsInput), (.needsInput, .paused): return true
        case (.running, .running): return true
        default: return false
        }
    }
}

public struct ExecutionEvent: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case observed
        case planned
        case decided
        case executed
        case verified
        case retried
        case status
        case message
        case warning
    }

    public let id: UUID
    public let timestamp: Date
    public let kind: Kind
    public let summary: String

    public init(id: UUID = UUID(), timestamp: Date, kind: Kind, summary: String) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.summary = summary
    }
}

public struct AgentRun: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let trigger: RunTrigger
    public let instruction: String
    public var status: RunStatus
    public let startedAt: Date
    public var endedAt: Date?
    public var actionCount: Int
    public var finalResponse: String?
    public var events: [ExecutionEvent]

    public init(
        id: UUID = UUID(),
        trigger: RunTrigger,
        instruction: String,
        status: RunStatus = .queued,
        startedAt: Date,
        endedAt: Date? = nil,
        actionCount: Int = 0,
        finalResponse: String? = nil,
        events: [ExecutionEvent] = []
    ) {
        self.id = id
        self.trigger = trigger
        self.instruction = instruction
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.actionCount = actionCount
        self.finalResponse = finalResponse
        self.events = events
    }

    /// Applies a status change when the transition is legal.
    @discardableResult
    public mutating func transition(to next: RunStatus, at date: Date) -> Bool {
        guard status.canTransition(to: next) else { return false }
        status = next
        if next.isTerminal { endedAt = date }
        return true
    }
}
