import Combine
import Foundation
import PulseNotchCore

@MainActor
final class GitHubFeatureModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded([GitHubPullRequest])
        case unavailable(Reason)

        enum Reason: Equatable {
            case commandLineToolMissing
            case requestFailed
        }
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var actionSessions: [GitHubActionSession] = []

    private let provider: any GitHubActivityProviding
    private var actionTracker = GitHubActionTracker()

    var notificationActionSessions: [GitHubActionSession] {
        actionTracker.notificationSessions
    }

    init(provider: any GitHubActivityProviding) {
        self.provider = provider
    }

    func refresh(repositories: [GitHubRepository] = [], at date: Date = Date()) async {
        do {
            let activity = try await provider.activity(repositories: repositories)
            actionSessions = actionTracker.update(
                runs: activity.actionRuns,
                at: date
            )
            state = .loaded(activity.pullRequests)
        } catch GitHubCLIProviderError.executableNotFound {
            state = .unavailable(.commandLineToolMissing)
        } catch {
            state = .unavailable(.requestFailed)
        }
    }

    func acknowledgeCompletedActions() {
        guard actionTracker.acknowledgeCompletedSessions() else { return }
        actionSessions = actionTracker.sessions
    }
}
