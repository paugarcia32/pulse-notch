import Foundation
import PulseNotchCore
import Testing
@testable import PulseNotchApp

struct LocalCodingAgentProcessParserTests {
    @Test
    func capturesProcessStartTimeFromElapsedDuration() {
        let now = Date(timeIntervalSince1970: 10_000)

        let agent = LocalCodingAgentProcessParser.parse(
            "42 01:05 /opt/homebrew/bin/codex --quiet",
            at: now
        ).first

        #expect(agent?.processID == 42)
        #expect(agent?.startedAt == now.addingTimeInterval(-65))
    }

    @Test
    func detectsSupportedCommandLineAgents() {
        let output = """
          12 /opt/homebrew/bin/codex --quiet
          13 /Users/test/.local/bin/claude
          14 /usr/local/bin/cursor-agent run
          15 /usr/local/bin/node /usr/local/lib/node_modules/@openai/codex/bin/codex.js
          16 /usr/local/bin/node /usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js
          17 /Users/test/.local/bin/agy
          18 /Users/test/.opencode/bin/opencode
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
          20 /Applications/Cursor.app/Contents/MacOS/Cursor
          21 /Applications/ChatGPT.app/Contents/Resources/codex app-server
          22 /bin/zsh -c codex --quiet
          23 /usr/bin/rg codex
          24 /usr/local/bin/codex app-server --listen stdio://
          25 /Users/test/.local/bin/agy --print /usage --print-timeout 20s
        """

        #expect(LocalCodingAgentProcessParser.parse(output).isEmpty)
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
          11 03:00 /Applications/OpenCode.app/Contents/MacOS/OpenCode
          12 03:00 /Applications/OpenCode.app/Contents/Frameworks/OpenCode Helper.app/Contents/MacOS/OpenCode Helper --type=renderer
        """

        #expect(OpenCodeDesktopSessionReader.launchDate(in: processes, at: now) == now.addingTimeInterval(-180))
        #expect(LocalCodingAgentProcessParser.parse(processes, at: now).isEmpty)
    }

    @Test
    func desktopOpenCodeOnlyReportsUnfinishedLatestResponsesFromCurrentLaunch() throws {
        let rows = try CommandOutput.read(
            executable: "/usr/bin/sqlite3",
            arguments: ["-json", ":memory:", """
                CREATE TABLE session (id TEXT, title TEXT, directory TEXT);
                CREATE TABLE message (id TEXT, session_id TEXT, time_created INTEGER, data TEXT);
                INSERT INTO session VALUES ('active', 'Current task', '/tmp/project');
                INSERT INTO session VALUES ('completed', 'Done', '/tmp/project');
                INSERT INTO session VALUES ('waiting', 'Waiting', '/tmp/project');
                INSERT INTO session VALUES ('stale', 'Old task', '/tmp/project');
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
    func desktopOpenCodeWithNoActiveResponsesReportsNoSessions() throws {
        #expect(try OpenCodeDesktopSessionReader.parse(
            "",
            launchedAt: Date(timeIntervalSince1970: 1_500)
        ).isEmpty)
    }
}
