import Foundation
import PulseNotchCore
import Testing
@testable import PulseNotchApp

struct LocalCodingAgentProcessParserTests {
    @Test(arguments: ["/Applications/Claude.app", "/Users/test/Applications/Claude.app", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"])
    func detectsClaudeInstallationWhenGUIPathDoesNotIncludeItsCLI(path: String) {
        #expect(LocalCodingAgentInstallation.installedKinds(
            home: "/Users/test", searchPaths: ["/usr/bin", "/bin"],
            fileExists: { $0 == path }
        ) == [.claude])
    }

    @Test
    func capturesProcessStartTimeFromElapsedDuration() {
        let now = Date(timeIntervalSince1970: 10_000)

        let agent = LocalCodingAgentProcessParser.parse(
            "42 1 01:05 /opt/homebrew/bin/codex --quiet",
            at: now
        ).first

        #expect(agent?.processID == 42)
        #expect(agent?.startedAt == now.addingTimeInterval(-65))
    }

    @Test
    func detectsSupportedCommandLineAgents() {
        let output = """
          12 1 00:01 /opt/homebrew/bin/codex --quiet
          13 1 00:01 /Users/test/.local/bin/claude
          14 1 00:01 /usr/local/bin/cursor-agent run
          15 1 00:01 /usr/local/bin/node /usr/local/lib/node_modules/@openai/codex/bin/codex.js
          16 1 00:01 /usr/local/bin/node /usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js
          17 1 00:01 /Users/test/.local/bin/agy
          18 1 00:01 /Users/test/.opencode/bin/opencode
        """

        let agents = LocalCodingAgentProcessParser.parse(output)

        #expect(
            agents.map(\.kind) == [
                .codex, .claude, .cursor, .codex, .claude, .antigravity, .opencode
            ]
        )
    }

    @Test
    func ignoresEditorAndDesktopApplicationProcesses() {
        let output = """
          20 1 00:01 /Applications/Cursor.app/Contents/MacOS/Cursor
          21 1 00:01 /Applications/ChatGPT.app/Contents/Resources/codex app-server
          22 1 00:01 /bin/zsh -c codex --quiet
          23 1 00:01 /usr/bin/rg codex
          24 1 00:01 /usr/local/bin/codex app-server --listen stdio://
          25 1 00:01 /Users/test/.local/bin/agy --print /usage --print-timeout 20s
        """

        #expect(LocalCodingAgentProcessParser.parse(output).isEmpty)
    }

    @Test
    func detectsEmbeddedDesktopClaudeWithoutCountingItsUIOrHelpers() {
        let processes = """
          10 1 05:00 /Applications/Claude.app/Contents/MacOS/Claude
          11 10 04:00 /Applications/Claude.app/Contents/Helpers/disclaimer
          12 11 03:00 /Users/test/Library/Application Support/Claude/claude-code/2.1.308/build/claude.app/Contents/MacOS/claude --name desktop
          13 12 02:00 /Users/test/Library/Application Support/Claude/claude-code/2.1.308/build/claude.app/Contents/MacOS/claude --name child
          20 11 01:00 /Users/test/Library/Application Support/Claude/claude-code/2.1.308/build/claude.app/Contents/MacOS/claude
          21 10 01:00 /Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper
          22 1 00:01 /bin/zsh -c /Users/test/Library/Application Support/Claude/claude-code/2.1.308/build/claude.app/Contents/MacOS/claude
        """

        let agents = LocalCodingAgentProcessParser.parse(processes)

        #expect(agents.map(\.id) == ["claude-12", "claude-20"])
        #expect(agents.first?.title == "desktop")
    }

    @Test
    func busyDesktopClaudeSessionsFeedCollapsedIndicatorsAndDynamicPages() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let processes = LocalCodingAgentProcessParser.parse(
            "12 1 03:00 /Users/test/Library/Application Support/Claude/claude-code/2.1.308/build/claude.app/Contents/MacOS/claude",
            at: now
        )
        let process = try #require(processes.first)
        let agent = try #require(try ClaudeSessionReader.parse(
            Data(#"{"pid":12,"sessionId":"session","status":"busy","startedAt":9820000,"statusUpdatedAt":9990000}"#.utf8),
            process: process, at: now
        ))
        var tracker = CodingAgentTracker()
        let sessions = tracker.update(active: [agent], at: now)
        let indicators = CollapsedNotchIndicators.make(
            schedule: nil, sessions: sessions, actionSessions: [], at: now,
            calendarReminderLeadTime: 600
        )
        let activity = DynamicPageActivity(
            calendar: false, agents: sessions.contains { $0.status == .running },
            github: false, media: false
        )

        #expect(indicators.map(\.id) == ["claude-session"])
        #expect(activity.visiblePages(from: [.summary, .agents], isEnabled: true) == [.summary, .agents])
    }

    @Test
    func claudeSubprocessesShareTheirAncestorAgentWithoutMergingIndependentSessions() {
        let processes = """
          10 1 05:00 /usr/local/bin/claude
          11 10 04:00 /bin/zsh -c task
          12 11 03:00 /usr/local/bin/claude --name researcher
          13 12 02:00 /usr/local/bin/claude --name tester
          20 1 01:00 /usr/local/bin/claude
        """

        let agents = LocalCodingAgentProcessParser.parse(processes)

        #expect(agents.map(\.id) == ["claude-10", "claude-20"])
    }

    @Test
    func codexGroupsRunningSubagentThreadsUnderTheirParent() throws {
        let rows = try CommandOutput.read(
            executable: "/usr/bin/sqlite3",
            arguments: ["-json", ":memory:", """
                CREATE TABLE thread_turns (thread_id TEXT, rollout_ordinal INTEGER, status TEXT, started_at INTEGER);
                CREATE TABLE thread_items (thread_id TEXT, rollout_ordinal INTEGER, item_type TEXT, item_json TEXT);
                INSERT INTO thread_turns VALUES ('root', 1, 'completed', 100);
                INSERT INTO thread_turns VALUES ('child', 1, 'inProgress', 200);
                INSERT INTO thread_turns VALUES ('grandchild', 1, 'inProgress', 300);
                INSERT INTO thread_turns VALUES ('separate', 1, 'inProgress', 400);
                INSERT INTO thread_items VALUES ('root', 1, 'subAgentActivity', '{"agentThreadId":"child"}');
                INSERT INTO thread_items VALUES ('child', 1, 'subAgentActivity', '{"agentThreadId":"grandchild"}');
                INSERT INTO thread_items VALUES ('root', 2, 'userMessage', '{"cwd":"/tmp/main"}');
                INSERT INTO thread_items VALUES ('separate', 1, 'userMessage', '{"cwd":"/tmp/other"}');
                """ + CodexSessionReader.activeSessionsQuery]
        )

        #expect(rows.contains("\"id\":\"root\""))
        #expect(rows.contains("\"id\":\"separate\""))
        #expect(!rows.contains("\"id\":\"child\""))
        #expect(!rows.contains("\"id\":\"grandchild\""))
        #expect(rows.contains("\"workingDirectory\":\"/tmp/main\""))
    }

    @Test
    func codexSessionQueryUsesOnlyTheLatestTurnInEachThread() {
        #expect(CodexSessionReader.activeSessionsQuery.contains("PARTITION BY t.thread_id"))
        #expect(CodexSessionReader.activeSessionsQuery.contains("t.recency = 1"))
    }

    @Test
    func detectsDesktopOpenCodeWithoutTreatingHelpersAsSessions() {
        let now = Date(timeIntervalSince1970: 10_000)
        let processes = """
          11 1 03:00 /Applications/OpenCode.app/Contents/MacOS/OpenCode
          12 11 03:00 /Applications/OpenCode.app/Contents/Frameworks/OpenCode Helper.app/Contents/MacOS/OpenCode Helper --type=renderer
        """

        #expect(OpenCodeDesktopSessionReader.launchDate(in: processes, at: now) == now.addingTimeInterval(-180))
        #expect(LocalCodingAgentProcessParser.parse(processes, at: now).isEmpty)
    }

    @Test
    func desktopOpenCodeOnlyReportsUnfinishedLatestResponsesFromCurrentLaunch() throws {
        let rows = try CommandOutput.read(
            executable: "/usr/bin/sqlite3",
            arguments: ["-json", ":memory:", """
                CREATE TABLE session (id TEXT, parent_id TEXT, title TEXT, directory TEXT);
                CREATE TABLE message (id TEXT, session_id TEXT, time_created INTEGER, data TEXT);
                INSERT INTO session VALUES ('active', NULL, 'Current task', '/tmp/project');
                INSERT INTO session VALUES ('completed', NULL, 'Done', '/tmp/project');
                INSERT INTO session VALUES ('waiting', NULL, 'Waiting', '/tmp/project');
                INSERT INTO session VALUES ('stale', NULL, 'Old task', '/tmp/project');
                INSERT INTO message VALUES ('1', 'active', 2000000, '{"role":"user"}');
                INSERT INTO message VALUES ('2', 'active', 2001000, '{"role":"assistant","time":{"created":2001000}}');
                INSERT INTO message VALUES ('3', 'completed', 2002000, '{"role":"assistant","time":{"completed":2003000}}');
                INSERT INTO message VALUES ('4', 'waiting', 2004000, '{"role":"assistant"}');
                INSERT INTO message VALUES ('5', 'waiting', 2005000, '{"role":"user"}');
                INSERT INTO message VALUES ('6', 'stale', 1000000, '{"role":"assistant"}');
                """ + OpenCodeDesktopSessionReader.activeSessionsQuery(
                    launchedAt: Date(timeIntervalSince1970: 1_500)
                )]
        )

        let agents = try OpenCodeDesktopSessionReader.parse(
            rows,
            launchedAt: Date(timeIntervalSince1970: 1_500)
        )

        #expect(agents.map(\.id) == ["opencode-active"])
        #expect(agents.first?.title == "Current task")
        #expect(agents.first?.workingDirectory == "/tmp/project")
    }

    @Test
    func desktopOpenCodeGroupsActiveSubagentsUnderTheirRootSession() throws {
        let rows = try CommandOutput.read(
            executable: "/usr/bin/sqlite3",
            arguments: ["-json", ":memory:", """
                CREATE TABLE session (id TEXT, parent_id TEXT, title TEXT, directory TEXT);
                CREATE TABLE message (id TEXT, session_id TEXT, time_created INTEGER, data TEXT);
                INSERT INTO session VALUES ('root', NULL, 'Main task', '/tmp/main');
                INSERT INTO session VALUES ('child-a', 'root', 'Research', '/tmp/other');
                INSERT INTO session VALUES ('child-b', 'root', 'Implementation', '/tmp/other');
                INSERT INTO session VALUES ('grandchild', 'child-a', 'Tests', '/tmp/other');
                INSERT INTO session VALUES ('separate', NULL, 'Another task', '/tmp/second');
                INSERT INTO message VALUES ('1', 'root', 2000000, '{"role":"assistant","time":{"completed":2000100}}');
                INSERT INTO message VALUES ('2', 'child-a', 2001000, '{"role":"assistant"}');
                INSERT INTO message VALUES ('3', 'child-b', 2002000, '{"role":"assistant"}');
                INSERT INTO message VALUES ('4', 'grandchild', 2003000, '{"role":"assistant"}');
                INSERT INTO message VALUES ('5', 'separate', 2004000, '{"role":"assistant"}');
                """ + OpenCodeDesktopSessionReader.activeSessionsQuery(
                    launchedAt: Date(timeIntervalSince1970: 1_500)
                )]
        )

        let agents = try OpenCodeDesktopSessionReader.parse(
            rows,
            launchedAt: Date(timeIntervalSince1970: 1_500)
        )

        #expect(agents.map(\.id) == ["opencode-root", "opencode-separate"])
        #expect(agents.first?.title == "Main task")
        #expect(agents.first?.workingDirectory == "/tmp/main")
    }

    @Test
    func desktopOpenCodeWithNoActiveResponsesReportsNoSessions() throws {
        #expect(try OpenCodeDesktopSessionReader.parse(
            "",
            launchedAt: Date(timeIntervalSince1970: 1_500)
        ).isEmpty)
    }
}
