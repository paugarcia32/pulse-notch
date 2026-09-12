import Foundation

public enum CodingAgentKind: String, CaseIterable, Hashable, Sendable {
    case codex
    case claude
    case cursor
    case antigravity
    case opencode

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .cursor: "Cursor Agent"
        case .antigravity: "Antigravity"
        case .opencode: "OpenCode"
        }
    }
}

public struct DetectedCodingAgent: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: CodingAgentKind
    public let title: String
    public let workingDirectory: String?
    public let gitBranch: String?
    public let startedAt: Date?
    public let processID: Int?

    public init(
        id: String,
        kind: CodingAgentKind,
        title: String,
        workingDirectory: String? = nil,
        gitBranch: String? = nil,
        startedAt: Date? = nil,
        processID: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.workingDirectory = workingDirectory
        self.gitBranch = gitBranch
        self.startedAt = startedAt
        self.processID = processID
    }
}

public protocol CodingAgentProviding: Sendable {
    func activeAgents() async throws -> [DetectedCodingAgent]
    func usage() async throws -> [CodingAgentUsageAvailability]
}

public struct CodingAgentUsage: Identifiable, Equatable, Sendable {
    public let kind: CodingAgentKind
    public let windows: [Window]

    public var id: CodingAgentKind { kind }

    public init(kind: CodingAgentKind, windows: [Window]) {
        self.kind = kind
        self.windows = windows
    }

    public struct Window: Identifiable, Equatable, Sendable {
        public let durationMinutes: Int?
        public let label: String?
        public let usedPercent: Double
        public let resetsAt: Date?

        public var id: String {
            "\(label ?? "")-\(durationMinutes ?? 0)-\(resetsAt?.timeIntervalSince1970 ?? 0)"
        }

        public var remainingPercent: Double {
            min(max(100 - usedPercent, 0), 100)
        }

        public init(
            durationMinutes: Int?,
            label: String? = nil,
            usedPercent: Double,
            resetsAt: Date?
        ) {
            self.durationMinutes = durationMinutes
            self.label = label
            self.usedPercent = usedPercent
            self.resetsAt = resetsAt
        }
    }
}

public enum CodingAgentUsageAvailability: Identifiable, Equatable, Sendable {
    case available(CodingAgentUsage)
    case unavailable(CodingAgentKind)

    public var id: CodingAgentKind {
        switch self {
        case let .available(usage): usage.kind
        case let .unavailable(kind): kind
        }
    }

    public var kind: CodingAgentKind {
        switch self {
        case let .available(usage): usage.kind
        case let .unavailable(kind): kind
        }
    }
}

public struct CodingAgentSession: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case running
        case completed(at: Date)
    }

    public let id: String
    public let kind: CodingAgentKind
    public let title: String
    public let detectedAt: Date
    public let workingDirectory: String?
    public let gitBranch: String?
    public let startedAt: Date
    public let status: Status

    public init(
        id: String,
        kind: CodingAgentKind,
        title: String,
        detectedAt: Date,
        workingDirectory: String? = nil,
        gitBranch: String? = nil,
        startedAt: Date? = nil,
        status: Status
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detectedAt = detectedAt
        self.workingDirectory = workingDirectory
        self.gitBranch = gitBranch
        self.startedAt = startedAt ?? detectedAt
        self.status = status
    }
}

public struct CodingAgentTracker: Sendable {
    public private(set) var sessions: [CodingAgentSession] = []
    private let completedRetention: TimeInterval
    private var acknowledgedCompletionIDs: Set<String> = []

    public var notificationSessions: [CodingAgentSession] {
        sessions.filter { session in
            switch session.status {
            case .running:
                true
            case .completed:
                !acknowledgedCompletionIDs.contains(session.id)
            }
        }
    }

    public init(completedRetention: TimeInterval = 5 * 60) {
        self.completedRetention = completedRetention
    }

    @discardableResult
    public mutating func update(
        active agents: [DetectedCodingAgent],
        at date: Date
    ) -> [CodingAgentSession] {
        let activeByID = Dictionary(
            agents.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let previousByID = Dictionary(
            sessions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var updated = activeByID.values.map { agent in
            CodingAgentSession(
                id: agent.id,
                kind: agent.kind,
                title: agent.title,
                detectedAt: previousByID[agent.id]?.detectedAt ?? date,
                workingDirectory: agent.workingDirectory
                    ?? previousByID[agent.id]?.workingDirectory,
                gitBranch: agent.gitBranch ?? previousByID[agent.id]?.gitBranch,
                startedAt: agent.startedAt ?? previousByID[agent.id]?.startedAt ?? date,
                status: .running
            )
        }

        for session in sessions where activeByID[session.id] == nil {
            let completedAt: Date
            switch session.status {
            case .running:
                completedAt = date
            case let .completed(previouslyCompletedAt):
                completedAt = previouslyCompletedAt
            }

            guard date.timeIntervalSince(completedAt) < completedRetention else {
                continue
            }

            updated.append(
                CodingAgentSession(
                    id: session.id,
                    kind: session.kind,
                    title: session.title,
                    detectedAt: session.detectedAt,
                    workingDirectory: session.workingDirectory,
                    gitBranch: session.gitBranch,
                    startedAt: session.startedAt,
                    status: .completed(at: completedAt)
                )
            )
        }

        sessions = updated.sorted(by: Self.sort)
        let completedIDs = Set(sessions.compactMap { session in
            if case .completed = session.status {
                return session.id
            }
            return nil
        })
        acknowledgedCompletionIDs.formIntersection(completedIDs)
        return sessions
    }

    @discardableResult
    public mutating func acknowledgeCompletedSessions() -> Bool {
        let previousCount = acknowledgedCompletionIDs.count
        acknowledgedCompletionIDs.formUnion(
            sessions.compactMap { session in
                if case .completed = session.status {
                    return session.id
                }
                return nil
            }
        )
        return acknowledgedCompletionIDs.count != previousCount
    }

    private static func sort(
        _ lhs: CodingAgentSession,
        _ rhs: CodingAgentSession
    ) -> Bool {
        switch (lhs.status, rhs.status) {
        case (.running, .completed):
            return true
        case (.completed, .running):
            return false
        default:
            if lhs.detectedAt != rhs.detectedAt {
                return lhs.detectedAt > rhs.detectedAt
            }
            return lhs.id < rhs.id
        }
    }
}
