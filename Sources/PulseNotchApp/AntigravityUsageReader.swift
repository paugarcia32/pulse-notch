import Foundation
import PulseNotchCore

enum AntigravityUsageReader {
    static var executableURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".local/bin/agy")
    }

    static func read(at executableURL: URL = executableURL) throws -> CodingAgentUsage? {
        let output = try CommandOutput.read(
            executable: executableURL.path,
            arguments: ["--print", "/usage", "--print-timeout", "20s"]
        )
        return parseUsage(output)
    }

    static func parseUsage(_ output: String) -> CodingAgentUsage? {
        let formatter = ISO8601DateFormatter()
        let windows = output.split(separator: "\n").compactMap { line -> CodingAgentUsage.Window? in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: true)
            guard
                columns.count == 4,
                columns[1] == "Weekly Limit Remaining",
                let remaining = Double(columns[2].dropLast()),
                let resetsAt = formatter.date(from: String(columns[3]))
            else {
                return nil
            }

            return CodingAgentUsage.Window(
                durationMinutes: 10_080,
                label: usageLabel(for: String(columns[0])),
                usedPercent: 100 - remaining,
                resetsAt: resetsAt
            )
        }

        guard !windows.isEmpty else {
            return nil
        }
        return CodingAgentUsage(kind: .antigravity, windows: windows)
    }

    private static func usageLabel(for category: String) -> String {
        switch category {
        case "Gemini Models": "Gemini"
        case "Claude and GPT models": "Claude/GPT"
        default: category.replacingOccurrences(of: " Models", with: "")
        }
    }
}
