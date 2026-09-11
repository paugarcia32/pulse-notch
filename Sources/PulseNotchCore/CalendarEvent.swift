import Foundation

public struct CalendarEventColor: Equatable, Sendable {
    public static let orange = CalendarEventColor(
        red: 1,
        green: 0.58,
        blue: 0
    )

    public let red: Double
    public let green: Double
    public let blue: Double
    public let opacity: Double

    public init(
        red: Double,
        green: Double,
        blue: Double,
        opacity: Double = 1
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
}

public struct CalendarEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let startsAt: Date
    public let endsAt: Date
    public let isAllDay: Bool
    public let calendarName: String
    public let calendarColor: CalendarEventColor
    public let location: String?
    public let notes: String?
    public let meetingURL: URL?

    public init(
        id: String,
        title: String,
        startsAt: Date,
        endsAt: Date,
        isAllDay: Bool = false,
        calendarName: String = "Calendar",
        calendarColor: CalendarEventColor = .orange,
        location: String? = nil,
        notes: String? = nil,
        meetingURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.isAllDay = isAllDay
        self.calendarName = calendarName
        self.calendarColor = calendarColor
        self.location = location
        self.notes = notes
        self.meetingURL = meetingURL
    }

    public func startsSoon(
        relativeTo date: Date,
        threshold: TimeInterval = 5 * 60
    ) -> Bool {
        let timeUntilStart = startsAt.timeIntervalSince(date)
        return timeUntilStart > 0 && timeUntilStart <= threshold
    }

    public func isInProgress(relativeTo date: Date) -> Bool {
        startsAt <= date && endsAt > date
    }
}

public protocol CalendarEventProviding: Sendable {
    func events(in interval: DateInterval) async throws -> [CalendarEvent]
}

public struct CalendarEventSchedule: Equatable, Sendable {
    public let events: [CalendarEvent]

    public init(events: [CalendarEvent]) {
        self.events = events.sorted {
            if $0.startsAt != $1.startsAt {
                return $0.startsAt < $1.startsAt
            }

            return $0.id < $1.id
        }
    }

    public func next(after date: Date) -> CalendarEvent? {
        events.first { $0.startsAt >= date }
    }

    public func events(
        on date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [CalendarEvent] {
        guard let day = calendar.dateInterval(of: .day, for: date) else {
            return []
        }

        return events.filter {
            $0.startsAt < day.end && $0.endsAt > day.start
        }
    }

    public func currentAndUpcoming(
        on date: Date,
        relativeTo now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [CalendarEvent] {
        let events = events(on: date, calendar: calendar)
        guard calendar.isDate(date, inSameDayAs: now) else {
            return events
        }

        return events.filter { !$0.isAllDay && $0.endsAt > now }
    }
}

public enum CalendarEventProviderError: Error, Equatable, Sendable {
    case accessDenied
    case unavailable
}

public enum MeetingLinkResolver {
    public static func resolve(
        eventURL: URL?,
        location: String?,
        notes: String?
    ) -> URL? {
        if let eventURL, isSupportedMeetingURL(eventURL) {
            return eventURL
        }

        return [location, notes]
            .compactMap { $0 }
            .lazy
            .compactMap(firstSupportedMeetingURL(in:))
            .first
    }

    private static func firstSupportedMeetingURL(in text: String) -> URL? {
        let pattern = #"https?://[^\s<>"']+"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range)
            .compactMap { Range($0.range, in: text) }
            .compactMap { match -> URL? in
                let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?)]}")
                let value = String(text[match])
                    .trimmingCharacters(in: trailingPunctuation)
                return URL(string: value)
            }
            .first(where: isSupportedMeetingURL)
    }

    private static func isSupportedMeetingURL(_ url: URL) -> Bool {
        guard
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            let host = url.host?.lowercased()
        else {
            return false
        }

        return host == "meet.google.com"
            || host == "zoom.us"
            || host.hasSuffix(".zoom.us")
            || host == "teams.microsoft.com"
            || host == "teams.live.com"
            || host == "webex.com"
            || host.hasSuffix(".webex.com")
    }
}
