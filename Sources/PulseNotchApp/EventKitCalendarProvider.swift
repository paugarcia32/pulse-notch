@preconcurrency import EventKit
import Foundation
import PulseNotchCore

actor EventKitCalendarProvider: CalendarEventProviding {
    private let eventStore: EKEventStore
    private let searchInterval: TimeInterval

    init(
        eventStore: EKEventStore = EKEventStore(),
        searchInterval: TimeInterval = 14 * 24 * 60 * 60
    ) {
        self.eventStore = eventStore
        self.searchInterval = searchInterval
    }

    func nextEvent(after date: Date) async throws -> CalendarEvent? {
        try await ensureCalendarAccess()

        let predicate = eventStore.predicateForEvents(
            withStart: date,
            end: date.addingTimeInterval(searchInterval),
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)
            .filter { event in
                event.status != .canceled
                    && currentUserHasNotDeclined(event)
            }
            .map(calendarEvent(from:))

        return NextCalendarEvent().select(from: events, after: date)
    }

    private func ensureCalendarAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return
        case .notDetermined:
            guard try await eventStore.requestFullAccessToEvents() else {
                throw CalendarEventProviderError.accessDenied
            }
        case .denied, .restricted, .writeOnly:
            throw CalendarEventProviderError.accessDenied
        @unknown default:
            throw CalendarEventProviderError.unavailable
        }
    }

    private func currentUserHasNotDeclined(_ event: EKEvent) -> Bool {
        event.attendees?
            .first(where: \.isCurrentUser)?
            .participantStatus != .declined
    }

    private func calendarEvent(from event: EKEvent) -> CalendarEvent {
        CalendarEvent(
            id: event.eventIdentifier ?? event.calendarItemIdentifier,
            title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? "Untitled event",
            startsAt: event.startDate,
            endsAt: event.endDate,
            meetingURL: MeetingLinkResolver.resolve(
                eventURL: event.url,
                location: event.location,
                notes: event.notes
            )
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
