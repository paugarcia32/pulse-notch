import Foundation
import Testing
@testable import PulseNotchCore

struct ActivityTimelineTests {
    @Test
    func higherPriorityActivitiesAppearFirst() {
        let now = Date(timeIntervalSince1970: 1_000)
        let passive = activity(
            id: 1,
            priority: .passive,
            occurredAt: now.addingTimeInterval(10)
        )
        let urgent = activity(
            id: 2,
            priority: .urgent,
            occurredAt: now
        )

        let timeline = ActivityTimeline(activities: [passive, urgent])

        #expect(timeline.activities == [urgent, passive])
    }

    @Test
    func newerActivitiesBreakPriorityTies() {
        let now = Date(timeIntervalSince1970: 1_000)
        let older = activity(
            id: 1,
            priority: .normal,
            occurredAt: now
        )
        let newer = activity(
            id: 2,
            priority: .normal,
            occurredAt: now.addingTimeInterval(10)
        )

        var timeline = ActivityTimeline()
        timeline.insert(older)
        timeline.insert(newer)

        #expect(timeline.activities == [newer, older])
    }

    private func activity(
        id: UInt8,
        priority: NotchActivity.Priority,
        occurredAt: Date
    ) -> NotchActivity {
        NotchActivity(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, id)),
            source: .system,
            title: "Activity \(id)",
            priority: priority,
            occurredAt: occurredAt
        )
    }
}
