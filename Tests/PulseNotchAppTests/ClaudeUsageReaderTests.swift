import Foundation
import Testing
@testable import PulseNotchApp

struct ClaudeUsageReaderTests {
    @Test
    func desktopHistoryUsesNewestSampleAndDoesNotInventResetTimes() throws {
        let data = Data(#"""
        {"version":2,"samples":[
          {"t":9900000,"org":"example","u":{"fh":22,"sd":13}},
          {"t":9000000,"org":"example","u":{"fh":80,"sd":60}}
        ]}
        """#.utf8)
        let usage = try ClaudeUsageReader.parseDesktopHistory(data, now: Date(timeIntervalSince1970: 10_000))

        #expect(usage?.kind == .claude)
        #expect(usage?.windows.map(\.durationMinutes) == [300, 10_080])
        #expect(usage?.windows.map(\.remainingPercent) == [78, 87])
        #expect(usage?.windows.allSatisfy { $0.resetsAt == nil } == true)
    }

    @Test(arguments: [9_099_000, 10_001_000])
    func desktopHistoryRejectsStaleAndFutureSamples(timestamp: Int) throws {
        let data = Data("{\"version\":2,\"samples\":[{\"t\":\(timestamp),\"u\":{\"fh\":20,\"sd\":40}}]}".utf8)
        #expect(try ClaudeUsageReader.parseDesktopHistory(data, now: Date(timeIntervalSince1970: 10_000)) == nil)
    }

    @Test
    func desktopHistoryHandlesPartialLimitsAndUnsupportedData() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let partial = Data(#"{"version":2,"samples":[{"t":10000000,"u":{"fh":null,"sd":40,"sn":90}}]}"#.utf8)
        let usage = try ClaudeUsageReader.parseDesktopHistory(partial, now: now)
        #expect(usage?.windows.map(\.durationMinutes) == [10_080])
        #expect(usage?.windows.first?.remainingPercent == 60)

        for input in [
            #"{"version":3,"samples":[]}"#,
            #"{"version":2,"samples":[]}"#,
            #"{"version":2,"samples":[{"t":10000000,"u":{"fh":-1,"sd":101}}]}"#
        ] {
            #expect(try ClaudeUsageReader.parseDesktopHistory(Data(input.utf8), now: now) == nil)
        }
    }

    @Test
    func availableUsageChoosesNewerSourceAndFallsBackWhenEitherSourceIsInvalid() throws {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let statusLine = directory.appending(path: "status-line.json")
        let desktop = directory.appending(path: "desktop.json")
        let now = Date(timeIntervalSince1970: 10_000)
        try Data(#"{"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":11000}}}"#.utf8).write(to: statusLine)
        try Data(#"{"version":2,"samples":[{"t":9900000,"u":{"fh":35,"sd":50}}]}"#.utf8).write(to: desktop)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 9_000)], ofItemAtPath: statusLine.path)

        #expect(ClaudeUsageReader.readAvailable(statusLineURL: statusLine, desktopURL: desktop, now: now)?.windows.first?.usedPercent == 35)

        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 9_950)], ofItemAtPath: statusLine.path)
        #expect(ClaudeUsageReader.readAvailable(statusLineURL: statusLine, desktopURL: desktop, now: now)?.windows.first?.usedPercent == 20)

        try Data("invalid".utf8).write(to: statusLine)
        #expect(ClaudeUsageReader.readAvailable(statusLineURL: statusLine, desktopURL: desktop, now: now)?.windows.first?.usedPercent == 35)

        try Data("invalid".utf8).write(to: desktop)
        #expect(ClaudeUsageReader.readAvailable(statusLineURL: statusLine, desktopURL: desktop, now: now) == nil)
        try Data(#"{"rate_limits":{"seven_day":{"used_percentage":40,"resets_at":20000}}}"#.utf8).write(to: statusLine)
        #expect(ClaudeUsageReader.readAvailable(statusLineURL: statusLine, desktopURL: desktop, now: now)?.windows.first?.usedPercent == 40)
    }

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

        let usage = try ClaudeUsageReader.read(at: url, now: Date(timeIntervalSince1970: 1_738_000_000))

        #expect(usage?.kind == .claude)
        #expect(usage?.windows.map(\.durationMinutes) == [300, 10_080])
        #expect(usage?.windows.map(\.remainingPercent) == [76.5, 58.8])
    }

    @Test
    func expiredSnapshotDoesNotKeepReportingOldUsage() throws {
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"rate_limits":{"five_hour":{"used_percentage":90,"resets_at":1000},"seven_day":{"used_percentage":40,"resets_at":3000}}}"#.utf8).write(to: url)

        let usage = try ClaudeUsageReader.read(at: url, now: Date(timeIntervalSince1970: 2000))
        #expect(usage?.windows.map(\.durationMinutes) == [10_080])
        #expect(try ClaudeUsageReader.read(at: url, now: Date(timeIntervalSince1970: 3000)) == nil)
    }

    @Test
    func absentRateLimitsDoNotBecomeContextUsage() throws {
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }

        for input in [
            #"{"context_window":{"used_percentage":80}}"#,
            #"{"rate_limits":null}"#,
            #"{"rate_limits":{}}"#
        ] {
            try Data(input.utf8).write(to: url)
            #expect(try ClaudeUsageReader.read(at: url, now: Date(timeIntervalSince1970: 1000)) == nil)
        }
    }

    @Test
    func snapshotWriterStoresOnlyRateLimits() throws {
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try ClaudeUsageReader.writeSnapshot(
            fromStatusLineInput: Data(#"{"session_id":"private-session","cwd":"/private/project","rate_limits":{"five_hour":{"used_percentage":20,"resets_at":3000}}}"#.utf8), to: url
        )
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(!saved.contains("private"))
        #expect(try ClaudeUsageReader.read(at: url, now: Date(timeIntervalSince1970: 1000))?.windows.first?.usedPercent == 20)
    }
}
