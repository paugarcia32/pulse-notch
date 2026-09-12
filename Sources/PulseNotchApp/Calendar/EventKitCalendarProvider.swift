@preconcurrency import AppKit
@preconcurrency import EventKit
import Foundation
import PulseNotchCore

actor EventKitCalendarProvider: CalendarEventProviding {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        try await ensureCalendarAccess()

        let predicate = eventStore.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: nil
        )

        return eventStore.events(matching: predicate)
            .filter { event in
                event.status != .canceled
                    && currentUserHasNotDeclined(event)
            }
            .map(calendarEvent(from:))
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
            isAllDay: event.isAllDay,
            calendarName: event.calendar.title,
            calendarColor: calendarColor(for: event),
            location: event.location?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty,
            notes: event.notes?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty,
            meetingURL: MeetingLinkResolver.resolve(
                eventURL: event.url,
                location: event.location,
                notes: event.notes
            )
        )
    }

    private func calendarColor(for event: EKEvent) -> CalendarEventColor {
        guard let color = NSColor(cgColor: event.calendar.cgColor)?
            .usingColorSpace(.sRGB)
        else {
            return .orange
        }

        return CalendarEventColor(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent),
            opacity: Double(color.alphaComponent)
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
