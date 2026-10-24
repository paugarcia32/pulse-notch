import Foundation
import Testing
@testable import PulseNotchCore

struct CodingAgentUsageWarningTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test(arguments: [0, 5, 20, 50, 100])
    func warningIncludesThresholdAndDisappearsAboveIt(threshold: Int) {
        #expect(CodingAgentUsageWarning.select(
            in: usage(remaining: Double(threshold)), remainingThreshold: threshold, at: now
        ) != nil)
        #expect(CodingAgentUsageWarning.select(
            in: usage(remaining: Double(threshold) + 0.5), remainingThreshold: threshold, at: now
        ) == nil)
    }

    @Test
    func choosesLowestRemainingWindowAcrossAgents() throws {
        let availability = usage(remaining: 20) + [.available(CodingAgentUsage(kind: .claude, windows: [
            .init(durationMinutes: 300, usedPercent: 40, resetsAt: nil),
            .init(durationMinutes: 10_080, usedPercent: 95, resetsAt: now.addingTimeInterval(60))
        ]))]
        let warning = try #require(CodingAgentUsageWarning.select(in: availability, at: now))
        #expect(warning.kind == .claude)
        #expect(warning.window.durationMinutes == 10_080)
        #expect(warning.window.remainingPercent == 5)
    }

    @Test
    func ignoresUnavailableInvalidAndExpiredLimits() {
        let invalidWindows = [Double.nan, .infinity, -.infinity, -1, 101].map {
            CodingAgentUsage.Window(durationMinutes: 300, usedPercent: $0, resetsAt: nil)
        }
        let expired = [-60.0, 0].map {
            CodingAgentUsage.Window(durationMinutes: 300, usedPercent: 100, resetsAt: now.addingTimeInterval($0))
        }
        #expect(CodingAgentUsageWarning.select(in: [
            .unavailable(.claude),
            .available(CodingAgentUsage(kind: .codex, windows: invalidWindows + expired))
        ], remainingThreshold: 100, at: now) == nil)
        #expect(CodingAgentUsageWarning.select(in: [], at: now) == nil)
    }

    @Test
    func exhaustedLimitDisappearsAtReset() {
        let availability = usage(remaining: 0, resetsAt: now.addingTimeInterval(60))
        #expect(CodingAgentUsageWarning.select(in: availability, remainingThreshold: 0, at: now) != nil)
        #expect(CodingAgentUsageWarning.select(in: availability, at: now.addingTimeInterval(60)) == nil)
    }

    private func usage(remaining: Double, resetsAt: Date? = nil) -> [CodingAgentUsageAvailability] {
        [.available(CodingAgentUsage(kind: .codex, windows: [
            .init(durationMinutes: 300, usedPercent: 100 - remaining, resetsAt: resetsAt)
        ]))]
    }
}
