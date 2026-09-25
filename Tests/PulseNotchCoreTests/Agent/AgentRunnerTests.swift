import Foundation
import Testing
@testable import PulseNotchCore

struct AgentRunnerTests {
    private func run(
        _ turns: [ScriptedTurn],
        configuration: AgentConfiguration = testConfiguration(),
        decision: FakeDecisionProvider = FakeDecisionProvider(),
        executor: FakeExecutor? = FakeExecutor(),
        clock: TestClock = TestClock(),
        criteria: String? = nil,
        instruction: String = "Save the document",
        control: RunControl = RunControl(),
        recorder: UpdateRecorder = UpdateRecorder(),
        lease: DesktopLease = DesktopLease()
    ) async -> (AgentRunOutcome, ScriptedLanguageProvider) {
        let language = ScriptedLanguageProvider(turns)
        let runner = AgentRunner(
            task: AgentTask(
                trigger: .chat(conversationID: UUID()),
                instruction: instruction,
                completionCriteria: criteria,
                configuration: configuration
            ),
            environment: AgentEnvironment(
                decision: decision,
                language: language,
                executor: executor,
                lease: lease,
                clock: clock
            ),
            control: control,
            onUpdate: recorder.handler
        )
        return (await runner.run(), language)
    }

    private static func operate(_ step: String, text: String? = nil) -> ScriptedTurn {
        let arguments = text.map { #"{"step":"\#(step)","text":"\#($0)"}"# } ?? #"{"step":"\#(step)"}"#
        return .respond(ScriptedLanguageProvider.call("operate", arguments))
    }

    @Test
    func plainChatCompletesWithoutConsultingTheDecisionProvider() async {
        let decision = FakeDecisionProvider()
        let recorder = UpdateRecorder()
        let (outcome, _) = await run(
            [.respond(LanguageResponse(text: "Hello!"))],
            decision: decision,
            recorder: recorder
        )

        #expect(outcome.status == .completed(evidence: "Hello!"))
        #expect(outcome.finalResponse == "Hello!")
        #expect(decision.requests.current.isEmpty)
        #expect(recorder.updates.current.contains(.assistantText("Hello!")))
    }

    @Test
    func theDecisionProviderOperatesTheScreenForEachLanguageModelStep() async {
        let executor = FakeExecutor()
        let decision = FakeDecisionProvider(choosing: ["click the “Save” button", "done"])
        let (outcome, language) = await run(
            [
                Self.operate("click the Save button"),
                .respond(ScriptedLanguageProvider.call("finish_task", #"{"summary":"Saved","evidence":"Title shows saved"}"#))
            ],
            decision: decision,
            executor: executor
        )

        #expect(outcome.status == .completed(evidence: "Title shows saved"))
        #expect(outcome.actionCount == 1)
        guard case .click(.element(let id, _)) = executor.executed.current.first else {
            Issue.record("Expected a click chosen by the decision provider")
            return
        }
        #expect(id == "e1")
        #expect(decision.requests.current.flatMap { $0.questions.map(\.id) } == ["action", "effect", "action"])
        let report = language.requests.current.last?.messages.last { $0.role == .tool }?.text ?? ""
        #expect(report.hasPrefix("Step done: click the Save button"))
    }

    @Test
    func theLanguageModelSuppliesTheTextThatTheDecisionProviderTypes() async {
        let area = AccessibleElement(id: "t", role: "AXTextArea", label: "Document")
        let executor = FakeExecutor(observations: [[area]])
        let decision = FakeDecisionProvider(choosing: ["type the text into the “Document” text area", "done"])
        let (_, _) = await run(
            [Self.operate("fill the note", text: "ciao"), .respond(LanguageResponse(text: "Written"))],
            decision: decision,
            executor: executor
        )

        #expect(executor.executed.current == [.typeText("ciao", into: .element(id: "t", observationID: executor.executed.current.first?.target?.observationID ?? UUID()))])
        let secondChoice = decision.requests.current.last { $0.questions.first?.id == "action" }
        let options = secondChoice.flatMap { request -> [DecisionOption]? in
            if case .choice(let options) = request.questions[0].kind { return options }
            return nil
        } ?? []
        #expect(!options.contains { $0.value.hasPrefix("type") })
    }

    @Test
    func repeatedAbstentionsReturnControlToTheLanguageModelAndThenPause() async {
        let decision = FakeDecisionProvider(choosing: ["abstain", "abstain", "abstain"])
        let recorder = UpdateRecorder()
        let (outcome, _) = await run(
            [Self.operate("do something vague"), Self.operate("try again"), Self.operate("once more")],
            decision: decision,
            recorder: recorder
        )

        guard case .paused(let reason) = outcome.status else {
            Issue.record("Expected a pause, got \(outcome.status)")
            return
        }
        #expect(reason?.contains("3 failed attempts") == true)
        #expect(recorder.events.filter { $0.kind == .retried }.count == 3)
    }

    @Test
    func staleTargetsAreRefreshedAndRepeatedFailuresPause() async {
        let executor = FakeExecutor(validation: { _ in .stale("The control moved.") })
        let decision = FakeDecisionProvider(choosing: Array(repeating: "click the “Save” button", count: 5))
        let (outcome, _) = await run([Self.operate("click Save")], decision: decision, executor: executor)

        #expect(executor.executed.current.isEmpty)
        guard case .paused = outcome.status else {
            Issue.record("Expected a pause, got \(outcome.status)")
            return
        }
    }

    @Test
    func supervisedModeWaitsForApprovalAndReportsADecline() async {
        let executor = FakeExecutor()
        let control = RunControl()
        let recorder = UpdateRecorder()
        let answering = Task {
            while !(await control.isAwaitingApproval) { await Task.yield() }
            await control.answerApproval(false)
        }
        let (outcome, language) = await run(
            [Self.operate("click Save"), .respond(LanguageResponse(text: "I will not save it."))],
            configuration: testConfiguration(mode: .supervised),
            decision: FakeDecisionProvider(choosing: ["click the “Save” button"]),
            executor: executor,
            control: control,
            recorder: recorder
        )
        await answering.value

        #expect(executor.executed.current.isEmpty)
        #expect(outcome.status == .completed(evidence: "I will not save it."))
        #expect(recorder.statuses.contains { if case .needsInput(.approval) = $0 { true } else { false } })
        let lastToolResult = language.requests.current.last?.messages.last { $0.role == .tool }?.text ?? ""
        #expect(lastToolResult.contains("declined"))
    }

    @Test
    func deniedApplicationMovesTheRunToNeedsInput() async {
        let executor = FakeExecutor()
        let (outcome, _) = await run(
            [.respond(ScriptedLanguageProvider.call("open_app", #"{"name":"Safari"}"#))],
            configuration: testConfiguration(restrictions: ApplicationRestrictions(deniedBundleIDs: ["com.apple.Safari"])),
            executor: executor
        )

        #expect(outcome.status == .needsInput(.unauthorizedApplication("Safari")))
        #expect(executor.executed.current.isEmpty)
    }

    @Test
    func stepsInADisallowedFrontmostApplicationNeedInput() async {
        let (outcome, _) = await run(
            [Self.operate("save")],
            configuration: testConfiguration(restrictions: ApplicationRestrictions(allowedBundleIDs: ["com.apple.Safari"]))
        )

        #expect(outcome.status == .needsInput(.unauthorizedApplication("TextEdit")))
    }

    @Test
    func reachingTheActionLimitNeedsInput() async {
        let executor = FakeExecutor()
        let (outcome, _) = await run(
            [Self.operate("press return twice")],
            configuration: testConfiguration(limits: RunLimits(maximumActions: 1)),
            decision: FakeDecisionProvider(choosing: ["press Return", "press Return"]),
            executor: executor
        )

        #expect(executor.executed.current.count == 1)
        #expect(outcome.status == .needsInput(.limitReached("Reached the limit of 1 action.")))
    }

    @Test
    func reachingTheTimeLimitNeedsInput() async {
        let clock = TestClock()
        let executor = FakeExecutor(clock: clock)
        let (outcome, _) = await run(
            [Self.operate("press return twice")],
            configuration: testConfiguration(limits: RunLimits(maximumDuration: 1)),
            decision: FakeDecisionProvider(choosing: ["press Return", "press Return"]),
            executor: executor,
            clock: clock
        )

        #expect(executor.executed.current.count == 1)
        #expect(outcome.status == .needsInput(.limitReached("Reached the time limit of 1 second.")))
    }

    @Test
    func riskyActionsNeedInputInAutonomousMode() async {
        let decision = FakeDecisionProvider(choosing: ["click the “Delete” button"]) { question in
            if case .noul = question.kind { return .noul(probabilityYes: 0.9, confidence: 0.9) }
            return FakeDecisionProvider.approving(question)
        }
        let executor = FakeExecutor(observations: [[AccessibleElement(id: "d", role: "AXButton", label: "Delete")]])
        let (outcome, _) = await run([Self.operate("clean up")], decision: decision, executor: executor)

        guard case .needsInput(.unresolvedIntent) = outcome.status else {
            Issue.record("Expected unresolved intent, got \(outcome.status)")
            return
        }
        #expect(executor.executed.current.isEmpty)
    }

    @Test
    func onlyPotentiallySensitiveActionsGetARiskCheck() {
        let observation = Observation(
            capturedAt: Date(timeIntervalSince1970: 0),
            applicationName: "Mail",
            bundleID: "com.apple.mail",
            elements: [
                AccessibleElement(id: "s", role: "AXButton", label: "Send"),
                AccessibleElement(id: "b", role: "AXButton", label: "Bold")
            ]
        )
        let target = { (id: String) in ActionTarget.element(id: id, observationID: observation.id) }

        #expect(AgentRunner.isPotentiallySensitive(.click(target("s")), in: observation))
        #expect(!AgentRunner.isPotentiallySensitive(.click(target("b")), in: observation))
        #expect(AgentRunner.isPotentiallySensitive(.pressKeys(KeyShortcut(key: "return")), in: observation))
        #expect(!AgentRunner.isPotentiallySensitive(.openApplication(name: "TextEdit"), in: observation))
        #expect(!AgentRunner.isPotentiallySensitive(.typeText("ciao", into: nil), in: observation))
    }

    @Test
    func goalsCompleteOnlyWithVerifiedEvidence() async {
        let completionChecks = Locked(0)
        let decision = FakeDecisionProvider { question in
            if question.id == "complete" {
                let check = completionChecks.withValue { $0 += 1; return $0 }
                return check == 1 ? .score(value: 1, level: 1, confidence: 0.8) : .score(value: 2, level: 2, confidence: 0.9)
            }
            return FakeDecisionProvider.approving(question)
        }
        let finish = ScriptedLanguageProvider.call("finish_task", #"{"summary":"Saved","evidence":"Title says Saved"}"#)
        let (outcome, _) = await run(
            [.respond(finish), .respond(finish)],
            decision: decision,
            criteria: "The window title contains Saved"
        )

        guard case .completed(let evidence) = outcome.status else {
            Issue.record("Expected completion, got \(outcome.status)")
            return
        }
        #expect(evidence.contains("Title says Saved"))
        #expect(evidence.contains("Verified by JEV"))
        #expect(completionChecks.current == 2)
    }

    @Test
    func stoppingCancelsOutstandingInference() async {
        let control = RunControl()
        let language = ScriptedLanguageProvider([.hang])
        let runner = AgentRunner(
            task: AgentTask(trigger: .chat(conversationID: UUID()), instruction: "Hi", configuration: testConfiguration()),
            environment: AgentEnvironment(decision: FakeDecisionProvider(), language: language, executor: nil, lease: DesktopLease()),
            control: control,
            onUpdate: { _ in }
        )
        let running = Task { await runner.run() }
        while language.requests.current.isEmpty { await Task.yield() }
        await control.stop()
        running.cancel()

        #expect(await running.value.status == .stopped)
    }

    @Test
    func providerFailuresFailTheRunWithoutFallingBack() async {
        let decision = FakeDecisionProvider()
        let (outcome, language) = await run([.fail(.unauthorized)], decision: decision)

        #expect(outcome.status == .failed(message: LanguageProviderError.unauthorized.userMessage))
        #expect(language.requests.current.count == 1)
        #expect(decision.requests.current.isEmpty)
    }

    @Test
    func stepsThatExceedTheDecisionContextReportInsufficientContext() async {
        let executor = FakeExecutor()
        let (outcome, _) = await run(
            [Self.operate("click Save")],
            decision: FakeDecisionProvider(contextLimit: 20, isLocal: true),
            executor: executor
        )

        guard case .needsInput(.insufficientContext) = outcome.status else {
            Issue.record("Expected insufficient context, got \(outcome.status)")
            return
        }
        #expect(executor.executed.current.isEmpty)
    }

    @Test
    func disabledComputerUseOffersNoDesktopTools() async {
        var configuration = testConfiguration()
        configuration.computerUseEnabled = false
        let (_, language) = await run([.respond(LanguageResponse(text: "ok"))], configuration: configuration)

        let tools = language.requests.current.first?.tools.map(\.name) ?? []
        #expect(tools == ["finish_task", "ask_user"])
    }

    @Test
    func visionModelsReviewAScreenshotAfterEveryStep() async {
        let hasImage: (LanguageRequest) -> Bool = { request in
            request.messages.contains { $0.content.contains { if case .imagePNG = $0 { true } else { false } } }
        }
        let (_, textOnly) = await run([Self.operate("save"), .respond(LanguageResponse(text: "ok"))])
        #expect(textOnly.requests.current.count == 2)
        #expect(!hasImage(textOnly.requests.current[1]))
        #expect(textOnly.requests.current.first?.tools.contains { $0.name == "capture_screen" } == false)

        let (_, vision) = await run(
            [Self.operate("save"), Self.operate("check"), .respond(LanguageResponse(text: "Looks right"))],
            configuration: testConfiguration(vision: true)
        )
        let requests = vision.requests.current
        #expect(requests.count == 3)
        #expect(hasImage(requests[1]))
        // Screenshots are ephemeral: only the latest one stays in the transcript.
        #expect(requests[2].messages.filter { $0.content.contains { if case .imagePNG = $0 { true } else { false } } }.count == 1)
    }

    @Test
    func secondDesktopRunWaitsForTheFirstToFinish() async {
        let lease = DesktopLease()
        let first = UUID()
        try? await lease.acquire(for: first)
        let recorder = UpdateRecorder()
        let executor = FakeExecutor()
        let waiting = Task {
            await run(
                [Self.operate("press return"), .respond(LanguageResponse(text: "ok"))],
                decision: FakeDecisionProvider(choosing: ["press Return"]),
                executor: executor,
                recorder: recorder,
                lease: lease
            )
        }
        while await lease.queuedRunIDs.isEmpty { await Task.yield() }
        #expect(executor.executed.current.isEmpty)
        #expect(recorder.statuses.contains(.queued))

        await lease.release(first)
        let (outcome, _) = await waiting.value
        #expect(outcome.status == .completed(evidence: "ok"))
        #expect(executor.executed.current.count == 1)
        #expect(await lease.currentHolder == nil)
    }
}
