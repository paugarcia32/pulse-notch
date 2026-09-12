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
        """

        #expect(LocalCodingAgentProcessParser.parse(output).isEmpty)
    }

    @Test
    func codexSessionQueryUsesOnlyTheLatestTurnInEachThread() {
        #expect(CodexSessionReader.activeSessionsQuery.contains("PARTITION BY t.thread_id"))
        #expect(CodexSessionReader.activeSessionsQuery.contains("t.recency = 1"))
    }
}
