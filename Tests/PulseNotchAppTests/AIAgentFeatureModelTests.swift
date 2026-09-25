import Foundation
import PulseNotchCore
import Testing
@testable import PulseNotchApp

final class MutableClock: AgentClock, @unchecked Sendable {
    private let date: Locked<Date>
    init(_ date: Date) { self.date = Locked(date) }
    var now: Date { date.current }
    func set(_ newDate: Date) { date.withValue { $0 = newDate } }
}

@MainActor
struct AIAgentFeatureModelTests {
    private struct Harness {
        let model: AIAgentFeatureModel
        let store: SQLiteAgentStore
        let clock: MutableClock
        let root: URL
        let defaults: UserDefaults
        let suite: String

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private static let chatReply = [
        #"data: {"choices":[{"delta":{"content":"Hi there"},"finish_reason":"stop"}]}"#,
        "data: [DONE]"
    ]

    private func makeHarness(
        id: String,
        configure: (inout AIAgentSettings) -> Void,
        credentials: InMemoryCredentialStore = InMemoryCredentialStore(),
        stubs: [StubURLProtocol.Stub] = [.sse(chatReply)],
        now: Date = Date(timeIntervalSince1970: 1_780_000_000)
    ) throws -> Harness {
        let root = FileManager.default.temporaryDirectory.appending(path: "PulseNotchAgentModel-\(UUID().uuidString)")
        let store = try SQLiteAgentStore(databaseURL: root.appending(path: "agent.sqlite"))
        let suite = "PulseNotchTests.\(id)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        var settings = AIAgentSettings()
        settings.hostedDataDisclosureAccepted = true
        configure(&settings)
        let settingsStore = AIAgentSettingsStore(defaults: defaults)
        settingsStore.save(settings)
        let manifest = RuntimeManifest(manifestVersion: 1, runtimes: [], decisionModels: [], languageModels: [])
        let runtimes = LocalRuntimeManager(manifest: manifest, root: root.appending(path: "runtimes"))
        let factory = AgentProviderFactory(
            credentials: credentials,
            runtimes: runtimes,
            llamaServer: ManagedLlamaServer(),
            session: StubURLProtocol.session(id: id, stubs: stubs)
        )
        let clock = MutableClock(now)
        let model = AIAgentFeatureModel(
            store: store,
            credentials: credentials,
            runtimes: runtimes,
            componentStates: nil,
            factory: factory,
            executor: nil,
            availability: AlwaysAvailableDesktop(),
            settingsStore: settingsStore,
            clock: clock
        )
        return Harness(model: model, store: store, clock: clock, root: root, defaults: defaults, suite: suite)
    }

    private func waitForIdle(_ model: AIAgentFeatureModel) async {
        for _ in 0..<500 where !model.liveRuns.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test
    func localEndpointsChatWithoutAnyAPIKeys() async throws {
        let harness = try makeHarness(id: #function) { settings in
            settings.decisionKind = .layaEndpoint
            settings.languageKind = .localEndpoint
            settings.localEndpointModel = "mimo"
        }
        defer { harness.cleanUp() }
        let model = harness.model
        await model.setEnabled(true)
        #expect(model.setupIssues().isEmpty)

        model.draft = "Hello"
        await model.sendDraft()
        await waitForIdle(model)

        #expect(model.chatEntries.map(\.text) == ["Hello", "Hi there"])
        #expect(model.settings.configuration().isFullyLocalInference)
        let sent = StubURLProtocol.recordedRequests(#function).first
        #expect(sent?.url?.host == "127.0.0.1")
        #expect(sent?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(try await harness.store.conversations().count == 1)
        #expect(model.unacknowledgedOutcome == .completed)
    }

    @Test
    func enablingComputerUseChecksTheModelAutomaticallyOnTheFirstRun() async throws {
        let toolCall = StubURLProtocol.Stub.sse([
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c","type":"function","function":{"name":"add_numbers","arguments":"{\"a\":2,\"b\":3}"}}]},"finish_reason":"tool_calls"}]}"#,
            "data: [DONE]"
        ])
        let vision = StubURLProtocol.Stub.sse([#"data: {"choices":[{"delta":{"content":"red"},"finish_reason":"stop"}]}"#, "data: [DONE]"])
        let harness = try makeHarness(
            id: #function,
            configure: { settings in
                settings.decisionKind = .layaEndpoint
                settings.languageKind = .localEndpoint
                settings.localEndpointModel = "mimo"
                settings.computerUseEnabled = true
            },
            stubs: [toolCall, vision, .sse(Self.chatReply)]
        )
        defer { harness.cleanUp() }
        let model = harness.model
        await model.setEnabled(true)
        #expect(model.settings.computerUseUnavailableReason != nil)

        model.draft = "Open Discord"
        await model.sendDraft()
        await waitForIdle(model)

        #expect(model.settings.capabilityReport?.toolCallsVerified == true)
        #expect(model.settings.capabilityReport?.visionVerified == true)
        #expect(model.settings.computerUseUnavailableReason == nil)
        #expect(model.settings.configuration().computerUseEnabled)
        #expect(StubURLProtocol.recordedRequests(#function).count == 3)
    }

    @Test
    func hostedProvidersRequireKeysAndTheDataDisclosure() async throws {
        let credentials = InMemoryCredentialStore()
        let harness = try makeHarness(id: #function, configure: { settings in
            settings.decisionKind = .jev
            settings.languageKind = .openRouter
            settings.openRouterModel = "openai/test"
            settings.hostedDataDisclosureAccepted = false
        }, credentials: credentials)
        defer { harness.cleanUp() }
        let model = harness.model
        await model.setEnabled(true)
        #expect(model.setupIssues().count == 3)

        model.setCredential("tsk", for: .typeSafe)
        model.setCredential("ork", for: .openRouter)
        model.settings.hostedDataDisclosureAccepted = true
        #expect(model.setupIssues().isEmpty)

        model.draft = "Hello"
        await model.sendDraft()
        await waitForIdle(model)
        #expect(model.chatEntries.last?.text == "Hi there")
        #expect(StubURLProtocol.recordedRequests(#function).first?.value(forHTTPHeaderField: "Authorization") == "Bearer ork")

        model.removeCredential(.openRouter)
        #expect(try credentials.secret(for: .openRouter) == nil)
        #expect(!model.hasCredential(.openRouter))
    }

    @Test
    func providerFailuresAreShownWithoutFallingBack() async throws {
        let harness = try makeHarness(
            id: #function,
            configure: { settings in
                settings.decisionKind = .layaEndpoint
                settings.languageKind = .localEndpoint
                settings.localEndpointModel = "mimo"
            },
            stubs: [.stub(404, json: #"{"error":{"message":"missing"}}"#)]
        )
        defer { harness.cleanUp() }
        let model = harness.model
        await model.setEnabled(true)
        model.draft = "Hello"
        await model.sendDraft()
        await waitForIdle(model)

        #expect(model.chatEntries.last?.text.contains("not available") == true)
        #expect(model.unacknowledgedOutcome == .failed)
        #expect(StubURLProtocol.recordedRequests(#function).count == 1)
    }

    @Test
    func dueRoutinesRunOnceAndMissedOnesAreOfferedAfterARestart() async throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let harness = try makeHarness(id: #function, configure: { settings in
            settings.decisionKind = .layaEndpoint
            settings.languageKind = .localEndpoint
            settings.localEndpointModel = "mimo"
        }, now: start)
        defer { harness.cleanUp() }
        let model = harness.model
        let utc = TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let components = calendar.dateComponents([.hour, .minute], from: start.addingTimeInterval(60))
        let routine = Routine(
            title: "Summary",
            instruction: "Summarize",
            time: LocalTime(hour: components.hour ?? 0, minute: components.minute ?? 0),
            timeZoneIdentifier: "UTC",
            createdAt: start
        )
        await model.setEnabled(true)
        await model.saveRoutine(routine)
        await model.evaluateRoutines()

        harness.clock.set(start.addingTimeInterval(90))
        await model.evaluateRoutines()
        await waitForIdle(model)
        await model.evaluateRoutines()

        let runs = try await harness.store.runs(forRoutine: routine.id, limit: 10)
        #expect(runs.count == 1)
        #expect(runs.first?.status == .completed(evidence: "Hi there"))

        // Pulse Notch was not running for two days.
        harness.clock.set(start.addingTimeInterval(2 * 24 * 60 * 60 + 3_600))
        await model.evaluateRoutines()
        #expect(model.missedOccurrences.count == 1)
        #expect(model.liveRuns.isEmpty)

        let missed = try #require(model.missedOccurrences.first)
        await model.dismissMissed(missed.occurrence.key)
        #expect(try await harness.store.missedOccurrences().isEmpty)
    }

    @Test
    func unfinishedRunsAreMarkedInterruptedOnLaunch() async throws {
        let harness = try makeHarness(id: #function) { _ in }
        defer { harness.cleanUp() }
        let run = AgentRun(trigger: .goal(goalID: UUID()), instruction: "x", status: .running, startedAt: Date(timeIntervalSince1970: 0))
        try await harness.store.saveRun(run)

        await harness.model.setEnabled(true)

        #expect(try await harness.store.run(id: run.id)?.status == .interrupted)
        #expect(harness.model.lastError?.contains("interrupted") == true)
    }

    @Test
    func goalsSaveWithoutRunningAndHistoryIsRetainedForTheConfiguredDays() async throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let harness = try makeHarness(id: #function, configure: { $0.retentionDays = 30 }, now: now)
        defer { harness.cleanUp() }
        let old = AgentRun(trigger: .chat(conversationID: UUID()), instruction: "old", status: .running, startedAt: now.addingTimeInterval(-40 * 86_400))
        var finished = old
        finished.transition(to: .completed(evidence: "ok"), at: now.addingTimeInterval(-40 * 86_400))
        try await harness.store.saveRun(finished)
        let model = harness.model

        await model.setEnabled(true)
        await model.saveGoal(Goal(title: "Tidy", instruction: "Tidy the desktop", completionCriteria: "No files on the desktop", createdAt: now))

        #expect(model.goals.first?.status == .idle)
        #expect(model.liveRuns.isEmpty)
        #expect(try await harness.store.run(id: old.id) == nil)
        #expect(try await harness.store.goals().count == 1)
    }

    @Test
    func disablingStopsRunsAndEmergencyStopStopsEverything() async throws {
        let harness = try makeHarness(
            id: #function,
            configure: { settings in
                settings.decisionKind = .layaEndpoint
                settings.languageKind = .localEndpoint
                settings.localEndpointModel = "mimo"
            },
            stubs: [.stub(200, json: "", delay: .seconds(30))]
        )
        defer { harness.cleanUp() }
        let model = harness.model
        await model.setEnabled(true)
        model.draft = "Take your time"
        await model.sendDraft()
        #expect(model.indicatorState == .running)

        model.stopAll()
        await waitForIdle(model)
        #expect(model.liveRuns.isEmpty)
        #expect(model.chatEntries.last?.text.hasPrefix("Stopped") == true)

        model.draft = "Again"
        await model.sendDraft()
        await model.setEnabled(false)
        await waitForIdle(model)
        #expect(model.liveRuns.isEmpty)
        #expect(!model.isEnabled)
    }
}
