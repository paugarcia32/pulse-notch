import Foundation
import Testing
@testable import PulseNotchApp

struct CodexUsageReaderTests {
    @Test
    func decodesPrimaryAndSecondaryRateLimitWindows() throws {
        let response = Data(#"""
        {
          "id": 2,
          "result": {
            "rateLimits": {
              "primary": {
                "usedPercent": 25,
                "windowDurationMins": 300,
                "resetsAt": 1730947200
              },
              "secondary": {
                "usedPercent": 40,
                "windowDurationMins": 10080,
                "resetsAt": 1730950800
              }
            }
          }
        }
        """#.utf8)

        let usage = try CodexUsageReader.decodeRateLimits(response)

        #expect(usage?.windows.map(\.durationMinutes) == [300, 10_080])
        #expect(usage?.windows.map(\.remainingPercent) == [75, 60])
    }
}
