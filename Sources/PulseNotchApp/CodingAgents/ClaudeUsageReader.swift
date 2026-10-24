import Foundation
import PulseNotchCore

enum ClaudeUsageReader {
    // Desktop samples at most once every 4.5 minutes. Allow a small number of
    // sampling intervals, but never present yesterday's plan history as current.
    static let desktopMaximumAge: TimeInterval = 15 * 60

    private struct DesktopHistory: Decodable {
        struct Sample: Decodable {
            struct Utilization: Decodable {
                let fh: Double?
                let sd: Double?
            }
            let t: TimeInterval
            let u: Utilization
        }
        let version: Int
        let samples: [Sample]
    }

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

    static var desktopHistoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Claude/plan-usage-history.json")
    }

    static func readAvailable(
        statusLineURL: URL = snapshotURL,
        desktopURL: URL = desktopHistoryURL,
        now: Date = Date()
    ) -> CodingAgentUsage? {
        let statusLine = try? read(at: statusLineURL, now: now)
        let desktop = try? desktopObservation(from: Data(contentsOf: desktopURL), now: now)
        guard let desktop else { return statusLine }
        let attributes = try? FileManager.default.attributesOfItem(atPath: statusLineURL.path)
        let statusLineDate = attributes?[.modificationDate] as? Date
        if let statusLine, let statusLineDate, statusLineDate > desktop.date {
            return statusLine
        }
        return desktop.usage
    }

    static func parseDesktopHistory(_ data: Data, now: Date) throws -> CodingAgentUsage? {
        try desktopObservation(from: data, now: now)?.usage
    }

    private static func desktopObservation(
        from data: Data,
        now: Date
    ) throws -> (usage: CodingAgentUsage, date: Date)? {
        let history = try JSONDecoder().decode(DesktopHistory.self, from: data)
        guard history.version == 2, let sample = history.samples.max(by: { $0.t < $1.t }) else {
            return nil
        }
        let date = Date(timeIntervalSince1970: sample.t / 1_000)
        let age = now.timeIntervalSince(date)
        guard age >= 0, age <= desktopMaximumAge else { return nil }
        let windows = [(sample.u.fh, 300), (sample.u.sd, 10_080)]
            .compactMap { percent, duration -> CodingAgentUsage.Window? in
                guard let percent, percent.isFinite, (0...100).contains(percent) else { return nil }
                // History contains plan percentages, but no reset timestamps.
                return CodingAgentUsage.Window(durationMinutes: duration, usedPercent: percent, resetsAt: nil)
            }
        guard !windows.isEmpty else { return nil }
        return (CodingAgentUsage(kind: .claude, windows: windows), date)
    }

    static func read(at url: URL = snapshotURL, now: Date = Date()) throws -> CodingAgentUsage? {
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        guard let rateLimits = snapshot.rateLimits else {
            return nil
        }
        let windows = [
            rateLimits.fiveHour.map { usageWindow($0, durationMinutes: 300) },
            rateLimits.sevenDay.map { usageWindow($0, durationMinutes: 10_080) }
        ].compactMap { $0 }.filter { ($0.resetsAt ?? .distantPast) > now }

        guard !windows.isEmpty else {
            return nil
        }
        return CodingAgentUsage(kind: .claude, windows: windows)
    }

    static func writeSnapshot(
        fromStatusLineInput data: Data,
        to url: URL = snapshotURL
    ) throws {
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Persist only rate limits, never the rest of the session payload.
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
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
