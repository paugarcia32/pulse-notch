import Foundation

public struct ActivityTimeline: Equatable, Sendable {
    public private(set) var activities: [NotchActivity]

    public init(activities: [NotchActivity] = []) {
        self.activities = Self.sorted(activities)
    }

    public mutating func replace(with activities: [NotchActivity]) {
        self.activities = Self.sorted(activities)
    }

    public mutating func insert(_ activity: NotchActivity) {
        activities.append(activity)
        activities = Self.sorted(activities)
    }

    private static func sorted(_ activities: [NotchActivity]) -> [NotchActivity] {
        activities.sorted {
            if $0.priority != $1.priority {
                return $0.priority > $1.priority
            }

            if $0.occurredAt != $1.occurredAt {
                return $0.occurredAt > $1.occurredAt
            }

            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

