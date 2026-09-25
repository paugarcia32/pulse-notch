import Foundation

public enum GoalStatus: String, Codable, Hashable, Sendable {
    case idle
    case running
    case paused
    case needsInput
    case completed
    case failed
    case cancelled
}

public struct Goal: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var instruction: String
    /// What must be observably true for the goal to count as complete.
    public var completionCriteria: String
    /// Overrides the global configuration when set.
    public var configuration: AgentConfiguration?
    public var limits: RunLimits
    public var status: GoalStatus
    public var runIDs: [UUID]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        instruction: String,
        completionCriteria: String,
        configuration: AgentConfiguration? = nil,
        limits: RunLimits = .default,
        status: GoalStatus = .idle,
        runIDs: [UUID] = [],
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.instruction = instruction
        self.completionCriteria = completionCriteria
        self.configuration = configuration
        self.limits = limits
        self.status = status
        self.runIDs = runIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// Weekdays numbered as in `Calendar` (1 is Sunday).
public enum Weekday: Int, Codable, CaseIterable, Hashable, Sendable, Comparable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    public static let everyDay = Set(Weekday.allCases)
    public static let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
}

public struct LocalTime: Codable, Hashable, Sendable, Comparable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    public var formatted: String { String(format: "%02d:%02d", hour, minute) }
}

public struct Routine: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var instruction: String
    public var weekdays: Set<Weekday>
    public var time: LocalTime
    /// IANA identifier; defaults to the user's current time zone at creation.
    public var timeZoneIdentifier: String
    public var isEnabled: Bool
    public var configuration: AgentConfiguration?
    public var limits: RunLimits
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        instruction: String,
        weekdays: Set<Weekday> = Weekday.everyDay,
        time: LocalTime,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        isEnabled: Bool = true,
        configuration: AgentConfiguration? = nil,
        limits: RunLimits = .default,
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.instruction = instruction
        self.weekdays = weekdays
        self.time = time
        self.timeZoneIdentifier = timeZoneIdentifier
        self.isEnabled = isEnabled
        self.configuration = configuration
        self.limits = limits
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }
}

/// Identifies one scheduled occurrence by the routine and its local calendar day,
/// so an occurrence runs at most once even across daylight-saving transitions.
public struct OccurrenceKey: Codable, Hashable, Sendable, Comparable {
    public let routineID: UUID
    /// `yyyy-MM-dd` in the routine's time zone.
    public let localDate: String

    public init(routineID: UUID, localDate: String) {
        self.routineID = routineID
        self.localDate = localDate
    }

    public static func < (lhs: OccurrenceKey, rhs: OccurrenceKey) -> Bool {
        (lhs.localDate, lhs.routineID.uuidString) < (rhs.localDate, rhs.routineID.uuidString)
    }
}

public struct RoutineOccurrence: Hashable, Sendable {
    public let key: OccurrenceKey
    public let scheduledAt: Date

    public init(key: OccurrenceKey, scheduledAt: Date) {
        self.key = key
        self.scheduledAt = scheduledAt
    }
}
