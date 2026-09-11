import Combine
import Foundation
import PulseNotchCore

@MainActor
final class CalendarFeatureModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(CalendarEventSchedule)
        case accessDenied
        case unavailable
    }

    @Published private(set) var state: State = .loading

    private let provider: any CalendarEventProviding

    init(provider: any CalendarEventProviding) {
        self.provider = provider
    }

    func refresh(at date: Date = Date()) async {
        let calendar = Calendar.autoupdatingCurrent
        guard
            let week = calendar.dateInterval(of: .weekOfYear, for: date),
            let end = calendar.date(byAdding: .day, value: 21, to: week.start)
        else {
            state = .unavailable
            return
        }

        do {
            let events = try await provider.events(
                in: DateInterval(start: week.start, end: end)
            )
            state = .loaded(CalendarEventSchedule(events: events))
        } catch CalendarEventProviderError.accessDenied {
            state = .accessDenied
        } catch {
            state = .unavailable
        }
    }
}
