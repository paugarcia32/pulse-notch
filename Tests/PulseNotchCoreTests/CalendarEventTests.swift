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
    func eventUsesConfiguredReminderWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let event = calendarEvent(startingAt: now.addingTimeInterval(10 * 60))

        #expect(
            event.startsSoon(relativeTo: now, threshold: 10 * 60)
        )
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

        let result = CalendarEventSchedule(events: [later, past, next])
            .next(after: now)

        #expect(result == next)
    }

    @Test
    func eventsOnDateIncludesEveryOverlappingEventInOrder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = Date(timeIntervalSince1970: 86_400)
        let overnight = calendarEvent(
            id: "overnight",
            startingAt: day.addingTimeInterval(-30 * 60),
            endingAt: day.addingTimeInterval(30 * 60)
        )
        let morning = calendarEvent(
            id: "morning",
            startingAt: day.addingTimeInterval(9 * 60 * 60)
        )
        let tomorrow = calendarEvent(
            id: "tomorrow",
            startingAt: day.addingTimeInterval(25 * 60 * 60)
        )

        let result = CalendarEventSchedule(
            events: [tomorrow, morning, overnight]
        ).events(on: day, calendar: calendar)

        #expect(result == [overnight, morning])
    }

    @Test
    func currentAndUpcomingIncludesOngoingAndFutureEvents() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = Date(timeIntervalSince1970: 86_400)
        let now = day.addingTimeInterval(10 * 60 * 60 + 20 * 60)
        let eventA = calendarEvent(
            id: "A",
            startingAt: day,
            endingAt: day.addingTimeInterval(12 * 60 * 60)
        )
        let eventB = calendarEvent(
            id: "B",
            startingAt: day.addingTimeInterval(60 * 60),
            endingAt: day.addingTimeInterval(2 * 60 * 60)
        )
        let eventC = calendarEvent(
            id: "C",
            startingAt: day.addingTimeInterval(4 * 60 * 60),
            endingAt: day.addingTimeInterval(6 * 60 * 60)
        )
        let eventD = calendarEvent(
            id: "D",
            startingAt: day.addingTimeInterval(10 * 60 * 60),
            endingAt: day.addingTimeInterval(10 * 60 * 60 + 30 * 60)
        )
        let eventE = calendarEvent(
            id: "E",
            startingAt: day.addingTimeInterval(14 * 60 * 60),
            endingAt: day.addingTimeInterval(16 * 60 * 60)
        )
        let allDay = calendarEvent(
            id: "all-day",
            startingAt: day,
            endingAt: day.addingTimeInterval(24 * 60 * 60),
            isAllDay: true
        )

        let result = CalendarEventSchedule(events: [
            eventE, eventC, allDay, eventA, eventD, eventB,
        ]).currentAndUpcoming(on: now, relativeTo: now, calendar: calendar)

        #expect(result == [eventA, eventD, eventE])
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
        startingAt date: Date,
        endingAt endDate: Date? = nil,
        isAllDay: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: "Planning",
            startsAt: date,
            endsAt: endDate ?? date.addingTimeInterval(30 * 60),
            isAllDay: isAllDay
        )
    }
}
