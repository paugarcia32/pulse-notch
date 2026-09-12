import Foundation
import Testing
@testable import PulseNotchApp

struct AntigravityUsageReaderTests {
    @Test
    func decodesWeeklyQuotaCategoriesFromCLIOutput() {
        let usage = AntigravityUsageReader.parseUsage("""
        Gemini Models\tWeekly Limit Remaining\t72%\t2026-09-18T22:28:02Z
        Claude and GPT models\tWeekly Limit Remaining\t46%\t2026-09-18T22:28:02Z
        """)

        #expect(usage?.kind == .antigravity)
        #expect(usage?.windows.map(\.label) == ["Gemini", "Claude/GPT"])
        #expect(usage?.windows.map(\.remainingPercent) == [72, 46])
        #expect(usage?.windows.map(\.durationMinutes) == [10_080, 10_080])
    }
}
