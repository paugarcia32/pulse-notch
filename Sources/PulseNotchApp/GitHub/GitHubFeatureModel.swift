import Combine
import Foundation
import PulseNotchCore

@MainActor
final class GitHubFeatureModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded([GitHubPullRequest])
        case unavailable
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var actionSessions: [GitHubActionSession] = []

    private let provider: any GitHubPullRequestProviding
    private var actionTracker = GitHubActionTracker()

    var notificationActionSessions: [GitHubActionSession] {
        actionTracker.notificationSessions
    }

    init(provider: any GitHubPullRequestProviding) {
        self.provider = provider
    }

    func refresh(at date: Date = Date()) async {
        do {
            let pullRequests = try await provider.pullRequests()
            actionSessions = actionTracker.update(
                runners: pullRequests.flatMap(\.actionRunners),
                at: date
            )
            state = .loaded(pullRequests)
        } catch {
            state = .unavailable
        }
    }

    func acknowledgeCompletedActions() {
        guard actionTracker.acknowledgeCompletedSessions() else { return }
        actionSessions = actionTracker.sessions
    }
}
