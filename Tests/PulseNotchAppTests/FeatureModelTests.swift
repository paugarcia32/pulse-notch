import Foundation
import PulseNotchCore
import Testing
@testable import PulseNotchApp

@MainActor
struct FeatureModelTests {
    @Test
    func calendarModelReportsDeniedAccess() async {
        let model = CalendarFeatureModel(provider: CalendarProviderFake(deniesAccess: true))

        await model.refresh(at: Date(timeIntervalSince1970: 1_000))

        #expect(model.state == .accessDenied)
    }

    @Test
    func codingAgentModelReportsDetectionFailure() async {
        let model = CodingAgentFeatureModel(
            provider: CodingAgentProviderFake(failsDetection: true)
        )

        await model.refresh(at: Date(timeIntervalSince1970: 1_000))

        #expect(model.state == .unavailable)
    }

    @Test
    func codingAgentModelRetainsPerAgentUsageAvailability() async {
        let model = CodingAgentFeatureModel(
            provider: CodingAgentProviderFake(
                usage: [.unavailable(.claude)]
            )
        )

        await model.refreshUsage()

        #expect(model.usageState == .loaded([.unavailable(.claude)]))
    }

    @Test
    func githubModelReportsProviderFailure() async {
        let model = GitHubFeatureModel(provider: GitHubProviderFake(fails: true))

        await model.refresh()

        #expect(model.state == .unavailable)
    }

    @Test
    func moreEventsLabelIncludesTheRemainingEventCount() {
        #expect(CalendarPage.moreEventsTitle(remainingCount: 3) == "Show 3 more events")
    }

    @Test
    func commandOutputTerminatesCommandsThatExceedTheirDeadline() {
        #expect(throws: CodingAgentProviderError.commandTimedOut) {
            _ = try CommandOutput.read(
                executable: "/bin/sleep",
                arguments: ["1"],
                timeout: 0
            )
        }
    }
}

private struct CalendarProviderFake: CalendarEventProviding {
    let deniesAccess: Bool

    func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        if deniesAccess {
            throw CalendarEventProviderError.accessDenied
        }
        return []
    }
}

private struct CodingAgentProviderFake: CodingAgentProviding {
    let failsDetection: Bool
    let usage: [CodingAgentUsageAvailability]

    init(
        failsDetection: Bool = false,
        usage: [CodingAgentUsageAvailability] = []
    ) {
        self.failsDetection = failsDetection
        self.usage = usage
    }

    func activeAgents() async throws -> [DetectedCodingAgent] {
        if failsDetection {
            throw CodingAgentProviderError.commandFailed
        }
        return []
    }

    func usage() async throws -> [CodingAgentUsageAvailability] {
        usage
    }
}

private struct GitHubProviderFake: GitHubPullRequestProviding {
    let fails: Bool

    func pullRequests() async throws -> [GitHubPullRequest] {
        if fails { throw CocoaError(.fileReadUnknown) }
        return []
    }
}
