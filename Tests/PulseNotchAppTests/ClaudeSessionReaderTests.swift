import Foundation
import PulseNotchCore
import Testing
@testable import PulseNotchApp

struct ClaudeSessionReaderTests {
    private let now = Date(timeIntervalSince1970: 100_000)

    private var process: DetectedCodingAgent {
        DetectedCodingAgent(
            id: "claude-42", kind: .claude, title: "Active coding session",
            startedAt: Date(timeIntervalSince1970: 1_000), processID: 42
        )
    }

    private func metadata(status: String, pid: Int = 42, startedAt: Int = 1_000_000) -> Data {
        Data("""
        {"pid":\(pid),"sessionId":"session","status":"\(status)",
         "cwd":"/tmp/project","name":"Implement feature","startedAt":\(startedAt),
         "statusUpdatedAt":2000000}
        """.utf8)
    }

    @Test
    func busySessionUsesWorkStateAndMetadataInsteadOfProcessAge() throws {
        let agent = try #require(try ClaudeSessionReader.parse(metadata(status: "busy"), process: process, at: now))

        #expect(agent.id == "claude-session")
        #expect(agent.title == "Implement feature")
        #expect(agent.workingDirectory == "/tmp/project")
        #expect(agent.processID == 42)
        #expect(agent.startedAt == Date(timeIntervalSince1970: 2_000))
    }

    @Test(arguments: ["idle", "waiting", "unknown", "working", ""])
    func openSessionIsNotActiveUnlessClaudeExplicitlyReportsBusy(status: String) throws {
        #expect(try ClaudeSessionReader.parse(metadata(status: status), process: process, at: now) == nil)
    }

    @Test
    func missingStateCannotEstablishRunningWork() throws {
        let data = Data(#"{"pid":42,"sessionId":"session","startedAt":1000000}"#.utf8)
        #expect(try ClaudeSessionReader.parse(data, process: process, at: now) == nil)
    }

    @Test
    func rejectsDifferentPIDAndRegistryFromBeforeCurrentProcess() throws {
        #expect(try ClaudeSessionReader.parse(metadata(status: "busy", pid: 99), process: process, at: now) == nil)
        #expect(try ClaudeSessionReader.parse(metadata(status: "busy", startedAt: 1000), process: process, at: now) == nil)
    }

    @Test
    func validatesProcessStartIdentityWhenRegistryProvidesIt() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        let matchingStart = formatter.string(from: Date(timeIntervalSince1970: 1000))
        let previousStart = formatter.string(from: Date(timeIntervalSince1970: 900))
        for (value, expected) in [(matchingStart, true), (previousStart, false), ("invalid", false)] {
            let data = Data("""
            {"pid":42,"sessionId":"session","status":"busy","startedAt":1000000,"procStart":"\(value)"}
            """.utf8)
            let agent = try ClaudeSessionReader.parse(data, process: process, at: now)
            #expect((agent != nil) == expected)
        }
    }

    @Test
    func missingOrMalformedMetadataDoesNotFallBackToProcessPresence() throws {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try ClaudeSessionReader.activeSessions(among: [process], in: directory, at: now).isEmpty)
        try Data("invalid".utf8).write(to: directory.appending(path: "42.json"))
        #expect(try ClaudeSessionReader.activeSessions(among: [process], in: directory, at: now).isEmpty)
        try metadata(status: "busy").write(to: directory.appending(path: "42.json"))
        #expect(try ClaudeSessionReader.activeSessions(among: [process], in: directory, at: now).count == 1)
        #expect(try ClaudeSessionReader.activeSessions(among: [], in: directory, at: now).isEmpty)
    }

    @Test
    func goingIdleStopsRunningIndicatorAndHidesDynamicAgentPageWithoutClosingProcess() throws {
        var tracker = CodingAgentTracker()
        let busy = try #require(try ClaudeSessionReader.parse(metadata(status: "busy"), process: process, at: now))
        tracker.update(active: [busy], at: now)
        let idle = try ClaudeSessionReader.parse(metadata(status: "idle"), process: process, at: now)
        let sessions = tracker.update(active: [idle].compactMap { $0 }, at: now.addingTimeInterval(2))
        let indicators = CollapsedNotchIndicators.make(
            schedule: nil, sessions: sessions, actionSessions: [], at: now,
            calendarReminderLeadTime: 600
        )
        let activity = DynamicPageActivity(
            calendar: false, agents: sessions.contains { $0.status == .running },
            github: false, media: false
        )

        #expect(!indicators.contains { $0.content == .runningAgent(.claude) })
        #expect(activity.visiblePages(from: [.summary, .agents], isEnabled: true) == [.summary])

        // An old process can begin a new task; age must not suppress real work.
        let resumed = tracker.update(active: [busy], at: now.addingTimeInterval(4))
        #expect(resumed.count == 1)
        #expect(resumed.first?.status == .running)
    }
}
