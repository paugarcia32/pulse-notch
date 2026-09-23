import Foundation
import PulseNotchCore
import Testing
@testable import PulseNotchApp

@MainActor
struct CodingAgentsPageTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func resetWithinTheHourShowsMinutesRatherThanAnExtraHour() {
        let window = CodingAgentUsage.Window(
            durationMinutes: 300,
            usedPercent: 87,
            resetsAt: now.addingTimeInterval(45 * 60)
        )

        #expect(CodingAgentsPage.resetDescription(window, at: now) == "resets in 45m")
    }

    @Test
    func imminentOrExpiredResetDoesNotClaimAnHourRemaining() {
        let imminent = CodingAgentUsage.Window(durationMinutes: 300, usedPercent: 100, resetsAt: now.addingTimeInterval(30))
        let expired = CodingAgentUsage.Window(durationMinutes: 300, usedPercent: 100, resetsAt: now.addingTimeInterval(-30))

        #expect(CodingAgentsPage.resetDescription(imminent, at: now) == "resets soon")
        #expect(CodingAgentsPage.resetDescription(expired, at: now) == "resets soon")
    }
}
