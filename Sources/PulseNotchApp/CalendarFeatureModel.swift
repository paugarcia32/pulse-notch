import Combine
import Foundation
import PulseNotchCore

@MainActor
final class CalendarFeatureModel: ObservableObject {
    enum State: Equatable {
        case loading
        case event(CalendarEvent)
        case noUpcomingEvent
        case accessDenied
        case unavailable
    }

    @Published private(set) var state: State = .loading

    private let provider: any CalendarEventProviding

    init(provider: any CalendarEventProviding) {
        self.provider = provider
    }

    func refresh(at date: Date = Date()) async {
        do {
            if let event = try await provider.nextEvent(after: date) {
                state = .event(event)
            } else {
                state = .noUpcomingEvent
            }
        } catch CalendarEventProviderError.accessDenied {
            state = .accessDenied
        } catch {
            state = .unavailable
        }
    }
}
