import Foundation
import Testing
@testable import PulseNotchCore

struct CalendarEventTests {
    @Test
    func eventStartingWithinFiveMinutesStartsSoon() {
        let now = Date(timeIntervalSince1970: 1_000)
        let event = calendarEvent(startingAt: now.addingTimeInterval(5 * 60))

        #expect(event.startsSoon(relativeTo: now))
    }

    @Test
    func eventMoreThanFiveMinutesAwayDoesNotStartSoon() {
        let now = Date(timeIntervalSince1970: 1_000)
        let event = calendarEvent(startingAt: now.addingTimeInterval(5 * 60 + 1))

        #expect(!event.startsSoon(relativeTo: now))
    }

    @Test
    func eventThatHasStartedDoesNotStartSoon() {
        let now = Date(timeIntervalSince1970: 1_000)
        let event = calendarEvent(startingAt: now)

        #expect(!event.startsSoon(relativeTo: now))
    }

    @Test
    func nextEventSelectsEarliestFutureEvent() {
        let now = Date(timeIntervalSince1970: 1_000)
        let later = calendarEvent(id: "later", startingAt: now.addingTimeInterval(600))
        let past = calendarEvent(id: "past", startingAt: now.addingTimeInterval(-60))
        let next = calendarEvent(id: "next", startingAt: now.addingTimeInterval(300))

        let result = NextCalendarEvent().select(
            from: [later, past, next],
            after: now
        )

        #expect(result == next)
    }

    @Test
    func meetingURLPrefersSupportedStructuredURL() {
        let eventURL = URL(string: "https://meet.google.com/abc-defg-hij")!

        let result = MeetingLinkResolver.resolve(
            eventURL: eventURL,
            location: "https://example.com",
            notes: "Backup: https://zoom.us/j/123456"
        )

        #expect(result == eventURL)
    }

    @Test
    func meetingURLCanBeExtractedFromNotes() {
        let result = MeetingLinkResolver.resolve(
            eventURL: nil,
            location: nil,
            notes: "Join at https://acme.zoom.us/j/123456."
        )

        #expect(result == URL(string: "https://acme.zoom.us/j/123456"))
    }

    @Test
    func unrelatedURLIsNotExposedAsMeetingLink() {
        let result = MeetingLinkResolver.resolve(
            eventURL: URL(string: "https://example.com/private-document"),
            location: "Office",
            notes: nil
        )

        #expect(result == nil)
    }

    private func calendarEvent(
        id: String = "event",
        startingAt date: Date
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: "Planning",
            startsAt: date,
            endsAt: date.addingTimeInterval(30 * 60)
        )
    }
}
