import Foundation
@testable import PulseNotchCore

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }

    var current: Value { withValue { $0 } }
}

enum ScriptedTurn: Sendable {
    case respond(LanguageResponse)
    case fail(LanguageProviderError)
    /// Never finishes until the consuming task is cancelled.
    case hang
}

final class ScriptedLanguageProvider: LanguageModelProvider, @unchecked Sendable {
    let isLocal: Bool
    private let turns: Locked<[ScriptedTurn]>
    let requests = Locked<[LanguageRequest]>([])

    init(isLocal: Bool = false, _ turns: [ScriptedTurn]) {
        self.isLocal = isLocal
        self.turns = Locked(turns)
    }

    func models() async throws -> [ModelInfo] { [] }

    func stream(_ request: LanguageRequest) -> AsyncThrowingStream<LanguageStreamEvent, Error> {
        requests.withValue { $0.append(request) }
        let turn = turns.withValue { $0.isEmpty ? ScriptedTurn.respond(LanguageResponse(text: "done")) : $0.removeFirst() }
        return AsyncThrowingStream { continuation in
            let task = Task {
                switch turn {
                case .respond(let response):
                    if !response.text.isEmpty { continuation.yield(.textDelta(response.text)) }
                    if !response.toolCalls.isEmpty { continuation.yield(.toolCalls(response.toolCalls)) }
                    continuation.yield(.finished(response.toolCalls.isEmpty ? .stop : .toolCalls, nil))
                    continuation.finish()
                case .fail(let error):
                    continuation.finish(throwing: error)
                case .hang:
                    do {
                        try await Task.sleep(for: .seconds(3600))
                    } catch {
                        continuation.finish(throwing: CancellationError())
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func call(_ name: String, _ arguments: String = "{}", id: String? = nil) -> LanguageResponse {
        LanguageResponse(toolCalls: [ToolCall(id: id ?? "call-\(name)-\(UUID().uuidString.prefix(4))", name: name, argumentsJSON: arguments)])
    }
}

final class FakeDecisionProvider: DecisionProvider, @unchecked Sendable {
    let contextLimit: Int
    let metadata: DecisionProviderMetadata
    let requests = Locked<[DecisionRequest]>([])
    private let answer: @Sendable (DecisionQuestion) -> DecisionAnswer
    /// Scripted action choices: each entry matches an option's description; `done`
    /// is chosen once the script runs out.
    private let script: Locked<[String]>

    init(
        contextLimit: Int = 32_000,
        isLocal: Bool = false,
        choosing script: [String] = [],
        answer: @escaping @Sendable (DecisionQuestion) -> DecisionAnswer = FakeDecisionProvider.approving
    ) {
        self.contextLimit = contextLimit
        self.metadata = DecisionProviderMetadata(provider: isLocal ? "Laya" : "JEV", model: "test", isLocal: isLocal)
        self.answer = answer
        self.script = Locked(script)
    }

    private func choose(_ question: DecisionQuestion) -> DecisionAnswer {
        guard case .choice(let options) = question.kind else { return answer(question) }
        let wanted = script.withValue { $0.isEmpty ? ActionCandidate.doneOption : $0.removeFirst() }
        let option = options.first { $0.value.contains(wanted) } ?? options.last!
        return .choice(selected: option.value, probabilities: [option.value: 0.9], confidence: 0.9)
    }

    func decide(_ request: DecisionRequest) async throws -> DecisionResponse {
        requests.withValue { $0.append(request) }
        var answers: [String: DecisionAnswer] = [:]
        for question in request.questions {
            answers[question.id] = question.id == "action" ? choose(question) : answer(question)
        }
        return DecisionResponse(answers: answers, metadata: metadata)
    }

    /// Approves every action, keeps the proposed target, and reports success.
    @Sendable static func approving(_ question: DecisionQuestion) -> DecisionAnswer {
        switch question.kind {
        case .noul: .noul(probabilityYes: 0.05, confidence: 0.95)
        case .choice: .choice(selected: "keep", probabilities: [:], confidence: 0.1)
        case .score(let levels): .score(value: Double(levels.count - 1), level: levels.count - 1, confidence: 0.9)
        }
    }
}

final class FakeExecutor: ComputerUseExecutor, @unchecked Sendable {
    private let observations: Locked<[[AccessibleElement]]>
    let executed = Locked<[ProposedAction]>([])
    let bundleID: String
    let validation: @Sendable (ProposedAction) -> TargetValidation?
    private let clock: TestClock?

    /// Each observation pops the next element list; the last one repeats.
    init(
        bundleID: String = "com.apple.TextEdit",
        observations: [[AccessibleElement]] = [[AccessibleElement(id: "e1", role: "AXButton", label: "Save")]],
        clock: TestClock? = nil,
        validation: @escaping @Sendable (ProposedAction) -> TargetValidation? = { _ in nil }
    ) {
        self.bundleID = bundleID
        self.observations = Locked(observations)
        self.clock = clock
        self.validation = validation
    }

    func observe(includeScreenshot: Bool) async throws -> Observation {
        let elements = observations.withValue { list in list.count > 1 ? list.removeFirst() : (list.first ?? []) }
        return Observation(
            capturedAt: clock?.now ?? Date(timeIntervalSince1970: 0),
            applicationName: "TextEdit",
            bundleID: bundleID,
            windowTitle: "Untitled",
            windowID: 1,
            displayID: 1,
            elements: elements,
            screenshot: includeScreenshot
                ? ScreenCapture(pngData: Data([0x89, 0x50]), pixelWidth: 100, pixelHeight: 50, displayID: 1, displayFrame: ScreenRect(x: 0, y: 0, width: 200, height: 100))
                : nil
        )
    }

    func validate(_ action: ProposedAction, against observation: Observation) async -> TargetValidation {
        if let override = validation(action) { return override }
        if case .element(let id, _) = action.target, observation.element(withID: id) == nil {
            return .stale("Element \(id) is gone.")
        }
        return .valid(action)
    }

    func execute(_ action: ProposedAction, in observation: Observation) async throws -> ActionResult {
        executed.withValue { $0.append(action) }
        clock?.advance(by: 1)
        return ActionResult(summary: action.summary)
    }

    func bundleID(forApplicationNamed name: String) async -> String? {
        name == "Safari" ? "com.apple.Safari" : bundleID
    }
}

final class TestClock: AgentClock, @unchecked Sendable {
    private let date: Locked<Date>

    init(_ date: Date = Date(timeIntervalSince1970: 1_000_000)) { self.date = Locked(date) }

    var now: Date { date.current }

    func advance(by interval: TimeInterval) { date.withValue { $0 += interval } }
}

final class UpdateRecorder: @unchecked Sendable {
    let updates = Locked<[AgentRunUpdate]>([])

    var handler: @Sendable (AgentRunUpdate) -> Void {
        { [updates] update in updates.withValue { $0.append(update) } }
    }

    var statuses: [RunStatus] {
        updates.current.compactMap { if case .status(let status) = $0 { status } else { nil } }
    }

    var events: [ExecutionEvent] {
        updates.current.compactMap { if case .event(let event) = $0 { event } else { nil } }
    }
}

func testConfiguration(
    mode: ExecutionMode = .autonomous,
    restrictions: ApplicationRestrictions = ApplicationRestrictions(),
    limits: RunLimits = .default,
    vision: Bool = false
) -> AgentConfiguration {
    AgentConfiguration(
        decision: .jev(model: "jev-latest"),
        language: .openRouter(model: "test/model"),
        executionMode: mode,
        restrictions: restrictions,
        limits: limits,
        visionVerified: vision
    )
}
