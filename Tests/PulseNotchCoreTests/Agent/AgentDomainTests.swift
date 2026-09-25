import Foundation
import Testing
@testable import PulseNotchCore

struct AgentDomainTests {
    // MARK: Provider combinations

    @Test(arguments: [
        (DecisionProviderSelection.jev(model: "jev-latest"), LanguageProviderSelection.openRouter(model: "a/b"), false),
        (.jev(model: "jev-latest"), .managedLocal(modelID: "mimo"), false),
        (.managedLaya(checkpoint: "laya-multilingual"), .openRouter(model: "a/b"), false),
        (.managedLaya(checkpoint: "laya-multilingual"), .managedLocal(modelID: "mimo"), true),
        (.layaEndpoint(url: URL(string: "http://127.0.0.1:8000")!, model: "laya"),
         .localEndpoint(url: URL(string: "http://localhost:8080")!, model: "m"), true),
        (.layaEndpoint(url: URL(string: "https://laya.example.com")!, model: "laya"),
         .localEndpoint(url: URL(string: "http://localhost:8080")!, model: "m"), false)
    ])
    func fullyLocalInferenceRequiresBothProvidersOnThisMac(
        decision: DecisionProviderSelection,
        language: LanguageProviderSelection,
        expected: Bool
    ) {
        #expect(AgentConfiguration(decision: decision, language: language).isFullyLocalInference == expected)
    }

    @Test
    func configurationRoundTripsThroughJSON() throws {
        let configuration = AgentConfiguration(
            decision: .managedLaya(checkpoint: "laya-multilingual"),
            language: .localEndpoint(url: URL(string: "http://127.0.0.1:8080")!, model: "mimo"),
            executionMode: .supervised,
            restrictions: ApplicationRestrictions(deniedBundleIDs: ["com.apple.Terminal"]),
            limits: RunLimits(maximumActions: 20, maximumDuration: 120, maximumReplans: 1)
        )
        let decoded = try JSONDecoder().decode(AgentConfiguration.self, from: JSONEncoder().encode(configuration))

        #expect(decoded == configuration)
    }

    @Test
    func restrictionsDenyBeforeAllowing() {
        let open = ApplicationRestrictions()
        let allowList = ApplicationRestrictions(allowedBundleIDs: ["com.apple.Safari"], deniedBundleIDs: ["com.apple.Safari"])

        #expect(open.permits(bundleID: "com.apple.Terminal"))
        #expect(!allowList.permits(bundleID: "com.apple.Safari"))
        #expect(!ApplicationRestrictions(allowedBundleIDs: ["com.apple.Safari"]).permits(bundleID: nil))
    }

    // MARK: Decision normalization

    @Test
    func choiceWithoutConfidenceUsesTheSelectedProbability() throws {
        let answer = try DecisionAnswer.normalizedChoice(
            selected: "b",
            probabilities: ["a": 0.2, "b": 0.8],
            confidence: nil,
            options: [DecisionOption("a"), DecisionOption("b")]
        )

        #expect(answer == .choice(selected: "b", probabilities: ["a": 0.2, "b": 0.8], confidence: 0.8))
    }

    @Test
    func choiceOutsideTheOfferedOptionsIsMalformed() {
        #expect(throws: DecisionProviderError.self) {
            try DecisionAnswer.normalizedChoice(selected: "z", probabilities: [:], confidence: 1, options: [DecisionOption("a")])
        }
    }

    @Test
    func fractionalScoresRoundToTheNearestLevel() throws {
        #expect(try DecisionAnswer.normalizedScore(value: 1.05, levelCount: 3, confidence: nil) == .score(value: 1.05, level: 1, confidence: 0.95))
        #expect(try DecisionAnswer.normalizedScore(value: 7, levelCount: 3, confidence: 0.4).scoreLevel == 2)
        #expect(throws: DecisionProviderError.self) {
            try DecisionAnswer.normalizedScore(value: .nan, levelCount: 3, confidence: nil)
        }
    }

    @Test
    func noulConfidenceFallsBackToTheMoreLikelyAnswer() throws {
        #expect(try DecisionAnswer.normalizedNoul(probabilityYes: 0.2, confidence: nil) == .noul(probabilityYes: 0.2, confidence: 0.8))
        #expect(try DecisionAnswer.normalizedNoul(probabilityYes: 1.4, confidence: 0.6) == .noul(probabilityYes: 1, confidence: 0.6))
    }

    @Test
    func questionShapeLimitsAreEnforced() {
        let tooManyOptions = (0...255).map { DecisionOption("o\($0)") }

        #expect(!DecisionQuestion(id: "q", instructions: "", kind: .choice(tooManyOptions)).isWellFormed)
        #expect(!DecisionQuestion(id: "q", instructions: "", kind: .choice([DecisionOption("a"), DecisionOption("a")])).isWellFormed)
        #expect(!DecisionQuestion(id: "q", instructions: "", kind: .score(levels: ["only"])).isWellFormed)
        #expect(DecisionQuestion(id: "q", instructions: "", kind: .noul(whenTrue: nil, whenFalse: nil)).isWellFormed)
    }

    // MARK: Streaming tool calls

    @Test
    func fragmentedToolCallsAreReassembledInIndexOrder() throws {
        var accumulator = ToolCallAccumulator()
        accumulator.append(index: 1, id: "b", name: "press_keys", argumentsFragment: #"{"keys""#)
        accumulator.append(index: 0, id: "a", name: "click", argumentsFragment: #"{"elem"#)
        accumulator.append(index: 0, id: nil, name: nil, argumentsFragment: #"ent_id":"e1"}"#)
        accumulator.append(index: 1, id: nil, name: nil, argumentsFragment: #":"return"}"#)

        #expect(try accumulator.completedCalls() == [
            ToolCall(id: "a", name: "click", argumentsJSON: #"{"element_id":"e1"}"#),
            ToolCall(id: "b", name: "press_keys", argumentsJSON: #"{"keys":"return"}"#)
        ])
    }

    @Test
    func emptyArgumentsBecomeAnEmptyObjectAndBrokenJSONIsRejected() throws {
        var empty = ToolCallAccumulator()
        empty.append(index: 0, id: "a", name: "observe_screen", argumentsFragment: nil)
        let emptyCalls = try empty.completedCalls()
        #expect(emptyCalls.first?.argumentsJSON == "{}")

        var broken = ToolCallAccumulator()
        broken.append(index: 0, id: "a", name: "click", argumentsFragment: #"{"element_id":"#)
        let brokenCalls = broken
        #expect(throws: LanguageProviderError.self) { try brokenCalls.completedCalls() }

        var nameless = ToolCallAccumulator()
        nameless.append(index: 0, id: "a", name: nil, argumentsFragment: "{}")
        let namelessCalls = nameless
        #expect(throws: LanguageProviderError.self) { try namelessCalls.completedCalls() }
    }

    // MARK: Tools

    @Test
    func toolCallsParseIntoTypedInvocations() throws {
        func parse(_ name: String, _ arguments: String) throws -> AgentToolInvocation {
            try AgentTools.parse(ToolCall(id: "1", name: name, argumentsJSON: arguments))
        }

        #expect(try parse("operate", #"{"step":"click Save"}"#) == .operate(step: "click Save", text: nil))
        #expect(try parse("operate", #"{"step":"type the note","text":"ciao"}"#) == .operate(step: "type the note", text: "ciao"))
        #expect(try parse("open_app", #"{"name":"TextEdit"}"#) == .openApplication(name: "TextEdit"))
        #expect(throws: AgentToolError.self) { try parse("open_url", #"{"url":"file:///etc/passwd"}"#) }
        #expect(throws: AgentToolError.self) { try parse("click", #"{"element_id":"e1"}"#) }
        #expect(throws: AgentToolError.self) { try parse("operate", "{}") }
    }

    @Test
    func languageModelsDirectStepsButNeverTargetControls() {
        let names = AgentTools.definitions(computerUse: true, vision: true).map(\.name)

        #expect(names == ["operate", "open_app", "open_url", "observe_screen", "capture_screen", "finish_task", "ask_user"])
        #expect(!AgentTools.definitions(computerUse: true, vision: false).map(\.name).contains("capture_screen"))
    }

    // MARK: Action candidates

    @Test
    func candidatesCoverControlsTypingKeysAndStepOutcomes() {
        let observation = Observation(
            capturedAt: Date(timeIntervalSince1970: 0),
            applicationName: "TextEdit",
            bundleID: "com.apple.TextEdit",
            elements: [
                AccessibleElement(id: "t", role: "AXTextArea", label: "Document"),
                AccessibleElement(id: "s", role: "AXButton", label: "Save"),
                AccessibleElement(id: "x", role: "AXStaticText", label: "Untitled"),
                AccessibleElement(id: "d", role: "AXButton", label: "Disabled", isEnabled: false),
                AccessibleElement(id: "p", role: "AXSecureTextField", label: "Password", isSecure: true)
            ]
        )
        let candidates = ActionCandidates.build(for: observation, step: "type the note", text: "ciao")
        let descriptions = candidates.map(\.description)

        #expect(descriptions.contains("type into textbox “Document”"))
        #expect(descriptions.contains("click button “Save”"))
        #expect(!descriptions.contains { $0.contains("Untitled") || $0.contains("Disabled") || $0.contains("Password") })
        #expect(candidates.suffix(2).map(\.option) == [ActionCandidate.doneOption, ActionCandidate.abstainOption])
        #expect(Set(candidates.map(\.option)).count == candidates.count)
        #expect(!ActionCandidates.build(for: observation, step: "save", text: nil).map(\.description).contains { $0.hasPrefix("type") })
    }

    @Test
    func candidatesHideMenusShowFieldValuesAndFingerprintsTrackChanges() {
        let elements = [
            AccessibleElement(id: "m", role: "AXMenuBarItem", label: "File"),
            AccessibleElement(id: "t", role: "AXTextField", label: "Name", value: "Pau")
        ]
        let observation = Observation(capturedAt: Date(timeIntervalSince1970: 0), applicationName: "App", bundleID: "a", elements: elements)
        let descriptions = ActionCandidates.build(for: observation, step: "rename", text: nil).map(\.description)

        #expect(descriptions.first == "click textbox “Name” = “Pau”")
        #expect(!descriptions.contains { $0.contains("File") })
        #expect(ActionCandidates.build(for: observation, step: "open the File menu", text: nil).map(\.description).contains("click menu “File”"))

        let edited = Observation(capturedAt: Date(timeIntervalSince1970: 1), applicationName: "App", bundleID: "a", elements: [elements[0], AccessibleElement(id: "t", role: "AXTextField", label: "Name", value: "Pau G")])
        #expect(ActionCandidates.fingerprint(observation) != ActionCandidates.fingerprint(edited))
        #expect(ActionCandidates.fingerprint(observation) == ActionCandidates.fingerprint(Observation(capturedAt: Date(timeIntervalSince1970: 9), applicationName: "App", bundleID: "a", elements: elements)))
    }

    @Test
    func candidateFittingKeepsGenericActionsAndReportsWhenNothingFits() throws {
        let many = (0..<120).map { AccessibleElement(id: "b\($0)", role: "AXButton", label: "Button number \($0) in a long toolbar") }
        let observation = Observation(capturedAt: Date(timeIntervalSince1970: 0), applicationName: "App", bundleID: "a", elements: many)
        let candidates = ActionCandidates.build(for: observation, step: "press button 7", text: nil)

        let fitted = try #require(ActionCandidates.fit(candidates, state: "{}", instructions: "Choose.", limit: 400))
        #expect(fitted.included.count < candidates.count)
        #expect(fitted.included.contains { $0.kind == .done } && fitted.included.contains { $0.kind == .abstain })
        #expect(ActionCandidates.fit(candidates, state: "{}", instructions: "Choose.", limit: 20) == nil)
    }

    // MARK: Context budget

    @Test
    func smallDecisionContextsKeepDecisiveControlsAndReportWhenTheyCannot() {
        let target = AccessibleElement(id: "e99", role: "AXButton", label: "Send invoice")
        let noise = (0..<200).map { AccessibleElement(id: "e\($0)", role: "AXStaticText", label: "Row \($0) of the quarterly report") }
        let ranked = ElementShortlist.ranked(noise + [target], relevantTo: "Send the invoice", pinned: ["e99"])
        let questions: ([AccessibleElement]) -> [DecisionQuestion] = { included in
            [DecisionQuestion(id: "target", instructions: "Which control?", kind: .choice(included.map { DecisionOption($0.id) }))]
        }

        let laya = DecisionStateBudget(limit: 1_024).fit(
            baseState: ["instruction": "Send the invoice"],
            candidates: ranked,
            requiredCount: 1,
            makeQuestions: questions
        )
        guard case .fits(_, let candidates, let omitted) = laya else {
            Issue.record("Expected the shortlist to fit Laya's context")
            return
        }
        #expect(candidates.first?.id == "e99")
        #expect(omitted > 0)

        let tiny = DecisionStateBudget(limit: 10).fit(
            baseState: ["instruction": "Send the invoice"],
            candidates: ranked,
            requiredCount: 1,
            makeQuestions: questions
        )
        guard case .insufficientContext = tiny else {
            Issue.record("Expected insufficient context")
            return
        }
    }

    @Test
    func secureFieldsNeverReachDecisionState() {
        let elements = [
            AccessibleElement(id: "p", role: "AXSecureTextField", label: "Password", value: "hunter2", isSecure: true),
            AccessibleElement(id: "u", role: "AXTextField", label: "User", value: "pau")
        ]

        #expect(elements[0].value == nil)
        #expect(ElementShortlist.ranked(elements, relevantTo: "password").map(\.id) == ["u"])
    }

    // MARK: Run status

    @Test
    func terminalRunStatusesCannotChange() {
        var run = AgentRun(trigger: .goal(goalID: UUID()), instruction: "x", status: .running, startedAt: Date(timeIntervalSince1970: 0))

        let completed = run.transition(to: .completed(evidence: "ok"), at: Date(timeIntervalSince1970: 5))
        #expect(completed)
        #expect(run.endedAt == Date(timeIntervalSince1970: 5))
        let restarted = run.transition(to: .running, at: Date(timeIntervalSince1970: 6))
        #expect(!restarted)
        #expect(!RunStatus.queued.canTransition(to: .completed(evidence: "")))
        #expect(RunStatus.paused(reason: nil).canTransition(to: .running))
    }

    // MARK: Lease

    @Test
    func cancelledLeaseWaitersLeaveTheQueue() async throws {
        let lease = DesktopLease()
        let holder = UUID()
        let waiter = UUID()
        try await lease.acquire(for: holder)
        let waiting = Task { try await lease.acquire(for: waiter) }
        while await lease.queuedRunIDs.isEmpty { await Task.yield() }
        waiting.cancel()

        await #expect(throws: CancellationError.self) { try await waiting.value }
        #expect(await lease.queuedRunIDs.isEmpty)
        await lease.release(holder)
        #expect(await lease.currentHolder == nil)
    }
}
