import Combine
import Foundation
import PulseNotchCore

@MainActor
final class CodingAgentFeatureModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded([CodingAgentSession])
        case unavailable
    }

    enum UsageState: Equatable {
        case loading
        case loaded([CodingAgentUsageAvailability])
        case unavailable
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var usageState: UsageState = .loading

    private let provider: any CodingAgentProviding
    private var tracker = CodingAgentTracker()

    var notificationSessions: [CodingAgentSession] {
        tracker.notificationSessions
    }

    init(provider: any CodingAgentProviding) {
        self.provider = provider
    }

    func refresh(at date: Date = Date()) async {
        do {
            let agents = try await provider.activeAgents()
            state = .loaded(tracker.update(active: agents, at: date))
        } catch {
            state = .unavailable
        }
    }

    func acknowledgeCompletedSessions() {
        guard tracker.acknowledgeCompletedSessions() else {
            return
        }
        state = .loaded(tracker.sessions)
    }

    func refreshUsage() async {
        do {
            usageState = .loaded(try await provider.usage())
        } catch {
            usageState = .unavailable
        }
    }
}
