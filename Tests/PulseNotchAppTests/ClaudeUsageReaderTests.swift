import Foundation
import Testing
@testable import PulseNotchApp

struct ClaudeUsageReaderTests {
    @Test
    func readsFiveHourAndWeeklyUsageFromStatusLineSnapshot() throws {
        let url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "claude-usage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data(#"""
        {
          "rate_limits": {
            "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
            "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
          }
        }
        """#.utf8).write(to: url)

        let usage = try ClaudeUsageReader.read(at: url)

        #expect(usage?.kind == .claude)
        #expect(usage?.windows.map(\.durationMinutes) == [300, 10_080])
        #expect(usage?.windows.map(\.remainingPercent) == [76.5, 58.8])
    }
}
