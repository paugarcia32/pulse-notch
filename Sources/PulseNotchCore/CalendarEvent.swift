import Foundation

public struct CalendarEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let startsAt: Date
    public let endsAt: Date
    public let meetingURL: URL?

    public init(
        id: String,
        title: String,
        startsAt: Date,
        endsAt: Date,
        meetingURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.meetingURL = meetingURL
    }

    public func startsSoon(
        relativeTo date: Date,
        threshold: TimeInterval = 5 * 60
    ) -> Bool {
        let timeUntilStart = startsAt.timeIntervalSince(date)
        return timeUntilStart > 0 && timeUntilStart <= threshold
    }
}

public protocol CalendarEventProviding: Sendable {
    func nextEvent(after date: Date) async throws -> CalendarEvent?
}

public struct NextCalendarEvent: Sendable {
    public init() {}

    public func select(
        from events: [CalendarEvent],
        after date: Date
    ) -> CalendarEvent? {
        events
            .filter { $0.startsAt >= date }
            .min {
                if $0.startsAt != $1.startsAt {
                    return $0.startsAt < $1.startsAt
                }

                return $0.id < $1.id
            }
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
