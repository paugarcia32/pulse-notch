import Foundation
import PulseNotchCore

enum ClaudeUsageReader {
    private struct Snapshot: Codable {
        let rateLimits: RateLimits?

        enum CodingKeys: String, CodingKey {
            case rateLimits = "rate_limits"
        }
    }

    private struct RateLimits: Codable {
        let fiveHour: Limit?
        let sevenDay: Limit?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    private struct Limit: Codable {
        let usedPercentage: Double
        let resetsAt: TimeInterval

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }

    }

    static var snapshotURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/pulse-notch-usage.json")
    }

    static func read(at url: URL = snapshotURL) throws -> CodingAgentUsage? {
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        guard let rateLimits = snapshot.rateLimits else {
            return nil
        }
        let windows = [
            rateLimits.fiveHour.map { usageWindow($0, durationMinutes: 300) },
            rateLimits.sevenDay.map { usageWindow($0, durationMinutes: 10_080) }
        ].compactMap { $0 }

        guard !windows.isEmpty else {
            return nil
        }
        return CodingAgentUsage(kind: .claude, windows: windows)
    }

    static func writeSnapshot(
        fromStatusLineInput data: Data,
        to url: URL = snapshotURL
    ) throws {
        _ = try JSONDecoder().decode(Snapshot.self, from: data)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func usageWindow(
        _ limit: Limit,
        durationMinutes: Int
    ) -> CodingAgentUsage.Window {
        CodingAgentUsage.Window(
            durationMinutes: durationMinutes,
            usedPercent: limit.usedPercentage,
            resetsAt: Date(timeIntervalSince1970: limit.resetsAt)
        )
    }
}
