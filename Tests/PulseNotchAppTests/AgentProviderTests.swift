import Foundation
import PulseNotchCore
import Testing
@testable import PulseNotchApp

/// Serves canned HTTP responses to a dedicated URLSession, so provider tests never
/// touch the network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        let status: Int
        let headers: [String: String]
        let body: Data
        /// Delays the response to exercise timeouts and cancellation.
        let delay: Duration?
    }

    private static let registry = Locked<[String: [Stub]]>([:])
    private static let requests = Locked<[String: [URLRequest]]>([:])
    private var loadingTask: Task<Void, Never>?

    static func session(id: String, stubs: [Stub]) -> URLSession {
        registry.withValue { $0[id] = stubs }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Stub-ID": id]
        return URLSession(configuration: configuration)
    }

    static func recordedRequests(_ id: String) -> [URLRequest] { requests.current[id] ?? [] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Stub-ID") ?? ""
        var recorded = request
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            recorded.httpBody = data
        }
        Self.requests.withValue { $0[id, default: []].append(recorded) }
        let stub = Self.registry.withValue { stubs -> Stub? in
            guard var list = stubs[id], !list.isEmpty else { return nil }
            let next = list.count > 1 ? list.removeFirst() : list[0]
            stubs[id] = list
            return next
        }
        guard let stub, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        // URLProtocol and its client are not Sendable; the loading system serializes their use.
        let context = UncheckedSendable((protocol: self, client: client))
        loadingTask = Task {
            if let delay = stub.delay {
                try? await Task.sleep(for: delay)
                if Task.isCancelled { return }
            }
            let (loader, client) = context.value
            let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)
            if let response { client?.urlProtocol(loader, didReceive: response, cacheStoragePolicy: .notAllowed) }
            client?.urlProtocol(loader, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(loader)
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
    }
}

struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

extension StubURLProtocol.Stub {
    static func stub(_ status: Int, json: String, headers: [String: String] = [:], delay: Duration? = nil) -> Self {
        Self(status: status, headers: headers.merging(["Content-Type": "application/json"]) { current, _ in current }, body: Data(json.utf8), delay: delay)
    }

    static func sse(_ lines: [String]) -> Self {
        Self(status: 200, headers: ["Content-Type": "text/event-stream"], body: Data(lines.joined(separator: "\n").utf8), delay: nil)
    }
}

private func requestBody(_ request: URLRequest?) throws -> [String: Any] {
    let data = try #require(request?.httpBody)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}

struct SystemOneWireTests {
    private let request = DecisionRequest(
        state: #"{"instruction":"Save"}"#,
        questions: [
            DecisionQuestion(id: "target", instructions: "Which?", kind: .choice([DecisionOption("e1", description: "Save"), DecisionOption("none")])),
            DecisionQuestion(id: "effect", instructions: "Worked?", kind: .score(levels: ["no", "unclear", "yes"])),
            DecisionQuestion(id: "aligned", instructions: "OK?", kind: .noul(whenTrue: "yes", whenFalse: "no"))
        ]
    )

    @Test
    func requestsUseTheSystemOneShape() throws {
        let body = try SystemOneWire.body(for: request, model: "jev-latest")
        let questions = try #require(body["questions"] as? [String: [String: Any]])

        #expect(body["model"] as? String == "jev-latest")
        #expect((body["state"] as? [String: Any])?["instruction"] as? String == "Save")
        #expect(questions["target"]?["type"] as? String == "choice")
        #expect((questions["target"]?["criteria"] as? [String: Any])?["none"] is NSNull)
        #expect(questions["effect"]?["criteria"] as? [String] == ["no", "unclear", "yes"])
        #expect((questions["aligned"]?["criteria"] as? [String: String])?["true"] == "yes")
    }

    @Test
    func jevAndLayaAnswersNormalizeToTheSameTypes() throws {
        let jev = #"{"model":"jev-1.13.0","answers":{"target":{"type":"choice","choice":"e1","probabilities":{"e1":0.9,"none":0.1},"confidence":0.9},"effect":{"type":"score","score":1.8,"legend":{},"probabilities":{}},"aligned":{"type":"noul","noul":0.7}},"usage":{"input_tokens":120,"output_tokens":0}}"#
        let laya = #"{"model":"laya-rl-agent","answers":{"target":{"type":"choice","choice":"e1","probabilities":{"e1":0.9,"none":0.1}},"effect":{"type":"score","score":1.8,"confidence":0.7},"aligned":{"type":"noul","noul":0.7,"confidence":0.6}}}"#
        let jevAnswers = try SystemOneWire.decodeAnswers(JSONSerialization.jsonObject(with: Data(jev.utf8)), for: request)
        let layaAnswers = try SystemOneWire.decodeAnswers(JSONSerialization.jsonObject(with: Data(laya.utf8)), for: request)

        #expect(jevAnswers.model == "jev-1.13.0")
        #expect(jevAnswers.inputTokens == 120)
        #expect(jevAnswers.answers["target"]?.selectedOption == "e1")
        #expect(layaAnswers.answers["target"]?.confidence == 0.9)
        #expect(jevAnswers.answers["effect"]?.scoreLevel == 2)
        #expect(jevAnswers.answers["aligned"] == .noul(probabilityYes: 0.7, confidence: 0.7))
        #expect(layaAnswers.answers["aligned"] == .noul(probabilityYes: 0.7, confidence: 0.6))
    }

    @Test
    func missingOrInvalidAnswersAreMalformed() {
        let missing = #"{"answers":{"target":{"choice":"e1"}}}"#
        let invalidChoice = #"{"answers":{"target":{"choice":"e9"},"effect":{"score":1},"aligned":{"noul":0.5}}}"#

        #expect(throws: DecisionProviderError.self) {
            try SystemOneWire.decodeAnswers(JSONSerialization.jsonObject(with: Data(missing.utf8)), for: request)
        }
        #expect(throws: DecisionProviderError.self) {
            try SystemOneWire.decodeAnswers(JSONSerialization.jsonObject(with: Data(invalidChoice.utf8)), for: request)
        }
    }
}

struct SystemOneDecisionProviderTests {
    private let request = DecisionRequest(
        state: "{}",
        questions: [DecisionQuestion(id: "q", instructions: "?", kind: .noul(whenTrue: nil, whenFalse: nil))]
    )

    @Test
    func jevSendsTheBearerKeyAndReportsMetadata() async throws {
        let session = StubURLProtocol.session(id: #function, stubs: [
            .stub(200, json: #"{"model":"jev-1.13.0","answers":{"q":{"type":"noul","noul":0.9}},"usage":{"input_tokens":7}}"#)
        ])
        let provider = SystemOneDecisionProvider.jev(model: "jev-latest", apiKey: "secret", session: session)
        let response = try await provider.decide(request)
        let sent = StubURLProtocol.recordedRequests(#function).first

        #expect(sent?.url?.absoluteString == "https://api.typesafe.ai/v1/systemone")
        #expect(sent?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(response.metadata == DecisionProviderMetadata(provider: "JEV", model: "jev-1.13.0", isLocal: false, inputTokens: 7))
        #expect(provider.contextLimit == 32_000)
    }

    @Test
    func rateLimitsRetryAfterTheServersDelay() async throws {
        let session = StubURLProtocol.session(id: #function, stubs: [
            .stub(429, json: "{}", headers: ["retry-after": "2"]),
            .stub(200, json: #"{"answers":{"q":{"noul":0.2}}}"#)
        ])
        let delays = Locked<[Duration]>([])
        let provider = SystemOneDecisionProvider(
            baseURL: URL(string: "http://127.0.0.1:8000")!,
            model: "laya",
            apiKey: nil,
            providerName: "Laya",
            contextLimit: 1_024,
            session: session,
            sleep: { duration in delays.withValue { $0.append(duration) } }
        )
        let response = try await provider.decide(request)

        #expect(response.answers["q"]?.probabilityYes == 0.2)
        #expect(delays.current == [.seconds(2)])
        #expect(response.metadata.isLocal)
        #expect(StubURLProtocol.recordedRequests(#function).first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test
    func httpFailuresMapToProviderErrors() async {
        let unauthorized = SystemOneDecisionProvider.jev(
            model: "jev-latest",
            apiKey: "bad",
            session: StubURLProtocol.session(id: "\(#function)-401", stubs: [.stub(401, json: "{}")])
        )
        await #expect(throws: DecisionProviderError.unauthorized) { try await unauthorized.decide(request) }

        let exhausted = SystemOneDecisionProvider(
            baseURL: SystemOneDecisionProvider.typeSafeBaseURL,
            model: "jev-latest",
            apiKey: "k",
            providerName: "JEV",
            contextLimit: 32_000,
            session: StubURLProtocol.session(id: "\(#function)-529", stubs: [.stub(529, json: "{}")]),
            maximumRetries: 1,
            sleep: { _ in }
        )
        await #expect(throws: DecisionProviderError.rateLimited(retryAfter: nil)) { try await exhausted.decide(request) }

        let malformed = SystemOneDecisionProvider.jev(
            model: "jev-latest",
            apiKey: "k",
            session: StubURLProtocol.session(id: "\(#function)-bad", stubs: [.stub(200, json: "not json")])
        )
        await #expect(throws: DecisionProviderError.malformedResponse("The response is not JSON.")) { try await malformed.decide(request) }
    }

    @Test
    func slowProvidersTimeOut() async {
        let provider = SystemOneDecisionProvider(
            baseURL: SystemOneDecisionProvider.typeSafeBaseURL,
            model: "jev-latest",
            apiKey: "k",
            providerName: "JEV",
            contextLimit: 32_000,
            session: StubURLProtocol.session(id: #function, stubs: [.stub(200, json: "{}", delay: .seconds(5))]),
            requestTimeout: 0.2
        )
        await #expect(throws: DecisionProviderError.timedOut) { try await provider.decide(request) }
    }
}

struct ChatCompletionStreamTests {
    @Test
    func textToolCallsAndUsageAreParsed() throws {
        var parser = ChatCompletionStreamParser()
        var events: [LanguageStreamEvent] = []
        for line in [
            ": OPENROUTER PROCESSING",
            #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#,
            "",
            #"data: {"choices":[{"delta":{"content":"lo"}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","type":"function","function":{"name":"click","arguments":"{\"element"}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"_id\":\"e1\"}"}}]},"finish_reason":"tool_calls"}]}"#,
            #"data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":4}}"#,
            "data: [DONE]",
            #"data: {"choices":[{"delta":{"content":"ignored"}}]}"#
        ] {
            events += try parser.consume(line: line)
        }
        events += parser.finish()
        events += try parser.completion()

        #expect(events == [
            .textDelta("Hel"),
            .textDelta("lo"),
            .toolCalls([ToolCall(id: "c1", name: "click", argumentsJSON: #"{"element_id":"e1"}"#)]),
            .finished(.toolCalls, TokenUsage(inputTokens: 10, outputTokens: 4))
        ])
    }

    @Test
    func midStreamErrorsAndMalformedChunksFail() {
        var parser = ChatCompletionStreamParser()
        #expect(throws: LanguageProviderError.streamFailed("Provider overloaded")) {
            try parser.consume(line: #"data: {"error":{"code":502,"message":"Provider overloaded"},"choices":[{"finish_reason":"error"}]}"#)
        }
        var malformed = ChatCompletionStreamParser()
        #expect(throws: LanguageProviderError.self) { try malformed.consume(line: "data: {oops") }
    }

    @Test
    func reasoningBlocksAreRemovedEvenAcrossChunks() {
        var filter = ThinkTagFilter()
        let visible = ["<thi", "nk>plan the", " steps</th", "ink>Answer", " <thin", "g>"].map { filter.filter($0) }.joined() + filter.flush()

        #expect(visible == "Answer <thing>")
    }
}

struct OpenAICompatibleProviderTests {
    @Test
    func streamsFromOpenRouterWithToolsAndImages() async throws {
        let session = StubURLProtocol.session(id: #function, stubs: [.sse([
            #"data: {"choices":[{"delta":{"content":"Done"},"finish_reason":"stop"}]}"#,
            "data: [DONE]"
        ])])
        let provider = OpenAICompatibleLanguageProvider(
            baseURL: OpenAICompatibleLanguageProvider.openRouterBaseURL,
            apiKey: "or-key",
            flavor: .openRouter,
            session: session
        )
        let response = try await provider.respond(to: LanguageRequest(
            model: "openai/gpt-test",
            messages: [ChatMessage(role: .user, content: [.text("Look"), .imagePNG(Data([1, 2]))])],
            tools: AgentTools.definitions(computerUse: true, vision: true)
        ))
        let sent = StubURLProtocol.recordedRequests(#function).first
        let body = try requestBody(sent)
        let message = try #require((body["messages"] as? [[String: Any]])?.first)
        let parts = try #require(message["content"] as? [[String: Any]])

        #expect(response.text == "Done")
        #expect(response.finishReason == .stop)
        #expect(sent?.value(forHTTPHeaderField: "Authorization") == "Bearer or-key")
        #expect(sent?.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect((body["tools"] as? [Any])?.count == 7)
        #expect(((parts[1]["image_url"] as? [String: Any])?["url"] as? String)?.hasPrefix("data:image/png;base64,") == true)
        #expect(!provider.isLocal)
    }

    @Test
    func unavailableModelsAndMissingCapabilitiesAreReported() async {
        let missing = OpenAICompatibleLanguageProvider(
            baseURL: URL(string: "http://127.0.0.1:8080/v1")!,
            apiKey: nil,
            flavor: .local,
            session: StubURLProtocol.session(id: "\(#function)-404", stubs: [.stub(404, json: #"{"error":{"message":"model not found"}}"#)])
        )
        await #expect(throws: LanguageProviderError.modelUnavailable("mimo")) {
            try await missing.respond(to: LanguageRequest(model: "mimo", messages: [.user("hi")]))
        }

        let noTools = OpenAICompatibleLanguageProvider(
            baseURL: OpenAICompatibleLanguageProvider.openRouterBaseURL,
            apiKey: "k",
            flavor: .openRouter,
            session: StubURLProtocol.session(id: "\(#function)-400", stubs: [.stub(400, json: #"{"error":{"message":"No endpoints found that support tool use"}}"#)])
        )
        await #expect(throws: LanguageProviderError.self) {
            try await noTools.respond(to: LanguageRequest(model: "x", messages: [.user("hi")], tools: AgentTools.definitions(computerUse: false, vision: false)))
        }
    }

    @Test
    func cancellingTheConsumerCancelsTheStream() async {
        let provider = OpenAICompatibleLanguageProvider(
            baseURL: OpenAICompatibleLanguageProvider.openRouterBaseURL,
            apiKey: "k",
            flavor: .openRouter,
            session: StubURLProtocol.session(id: #function, stubs: [.stub(200, json: "", delay: .seconds(30))])
        )
        let task = Task { try await provider.respond(to: LanguageRequest(model: "x", messages: [.user("hi")])) }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func openRouterCatalogExposesCapabilitiesAndPricingAndKeepsTheSelection() throws {
        let catalog = #"{"data":[{"id":"b/vision","name":"Vision","context_length":128000,"architecture":{"input_modalities":["text","image"]},"supported_parameters":["tools","tool_choice"],"pricing":{"prompt":"0.000001","completion":"0.000002","image":"0"}},{"id":"a/text","name":"Alpha","context_length":8000,"architecture":{"input_modalities":["text"]},"supported_parameters":[],"pricing":{"prompt":"0","completion":"0"}}]}"#
        let models = try OpenRouterCatalog.parse(Data(catalog.utf8))

        #expect(models.map(\.id) == ["a/text", "b/vision"])
        #expect(models[1].capabilities == ModelCapabilities(supportsTools: true, supportsVision: true, contextLength: 128_000))
        #expect(models[1].pricing?.prompt == Decimal(string: "0.000001"))
        #expect(OpenRouterCatalog.merge(models, preserving: "custom/model").first?.id == "custom/model")
        #expect(OpenRouterCatalog.merge(models, preserving: "a/text").count == 2)
    }

    @Test
    func capabilityProbeRequiresARealToolCallAndImageAnswer() async {
        let passing = ScriptedProvider(responses: [
            LanguageResponse(toolCalls: [ToolCall(id: "1", name: "add_numbers", argumentsJSON: #"{"a":2,"b":3}"#)]),
            LanguageResponse(text: "Red")
        ])
        let report = await CapabilityProbe(provider: passing).run(model: "mimo", checkVision: true)
        #expect(report.toolCallsVerified)
        #expect(report.visionVerified)

        let textOnly = ScriptedProvider(responses: [LanguageResponse(text: "The answer is 5"), LanguageResponse(text: "I cannot see images")])
        let failed = await CapabilityProbe(provider: textOnly).run(model: "m", checkVision: true)
        #expect(!failed.toolCallsVerified)
        #expect(!failed.readyForComputerUse)
        #expect(!failed.visionVerified)
    }
}

final class ScriptedProvider: LanguageModelProvider, @unchecked Sendable {
    let isLocal = true
    private let responses: Locked<[LanguageResponse]>

    init(responses: [LanguageResponse]) { self.responses = Locked(responses) }

    func models() async throws -> [ModelInfo] { [] }

    func stream(_ request: LanguageRequest) -> AsyncThrowingStream<LanguageStreamEvent, Error> {
        let response = responses.withValue { $0.isEmpty ? LanguageResponse() : $0.removeFirst() }
        return AsyncThrowingStream { continuation in
            if !response.text.isEmpty { continuation.yield(.textDelta(response.text)) }
            if !response.toolCalls.isEmpty { continuation.yield(.toolCalls(response.toolCalls)) }
            continuation.yield(.finished(.stop, nil))
            continuation.finish()
        }
    }
}

struct ManagedLayaProviderTests {
    private final class FakeTransport: LayaHelperTransport, @unchecked Sendable {
        let sent = Locked<[Data]>([])
        let reply: String

        init(reply: String) { self.reply = reply }

        func exchange(_ request: Data, id: String) async throws -> Data {
            sent.withValue { $0.append(request) }
            return Data(reply.utf8)
        }
    }

    @Test
    func helperResultsAreNormalizedWithoutAModelField() async throws {
        let transport = FakeTransport(reply: #"{"v":1,"id":"x","ok":true,"result":{"model":"laya-rl-agent","answers":{"q":{"type":"noul","noul":0.25,"confidence":0.8}}}}"#)
        let provider = ManagedLayaDecisionProvider(transport: transport, checkpoint: "laya-multilingual", contextLimit: 1_024)
        let response = try await provider.decide(DecisionRequest(
            state: "{}",
            questions: [DecisionQuestion(id: "q", instructions: "?", kind: .noul(whenTrue: nil, whenFalse: nil))]
        ))
        let sentData = try #require(transport.sent.current.first)
        let sentObject = try JSONSerialization.jsonObject(with: sentData)
        let sent = try #require(sentObject as? [String: Any])

        #expect(response.answers["q"] == .noul(probabilityYes: 0.25, confidence: 0.8))
        #expect(response.metadata.isLocal)
        #expect(sent["model"] == nil)
        #expect(sent["questions"] != nil)
    }

    @Test
    func helperErrorsBecomeUnavailable() async {
        let provider = ManagedLayaDecisionProvider(
            transport: FakeTransport(reply: #"{"v":1,"id":"x","ok":false,"error":"out of memory"}"#),
            checkpoint: "laya-multilingual",
            contextLimit: 1_024
        )
        await #expect(throws: DecisionProviderError.unavailable("out of memory")) {
            try await provider.decide(DecisionRequest(state: "{}", questions: [DecisionQuestion(id: "q", instructions: "?", kind: .noul(whenTrue: nil, whenFalse: nil))]))
        }
    }
}
