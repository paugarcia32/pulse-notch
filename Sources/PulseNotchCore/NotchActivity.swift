import Foundation

public struct NotchActivity: Identifiable, Equatable, Sendable {
    public enum Source: String, CaseIterable, Sendable {
        case calendar
        case github
        case agent
        case media
        case system
    }

    public enum Priority: Int, Comparable, Sendable {
        case passive
        case normal
        case important
        case urgent

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let id: UUID
    public let source: Source
    public let title: String
    public let detail: String?
    public let priority: Priority
    public let occurredAt: Date

    public init(
        id: UUID = UUID(),
        source: Source,
        title: String,
        detail: String? = nil,
        priority: Priority = .normal,
        occurredAt: Date
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.detail = detail
        self.priority = priority
        self.occurredAt = occurredAt
    }
}

