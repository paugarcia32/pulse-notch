import Foundation
import PulseNotchCore

/// Streams chat completions from OpenRouter, the managed `llama.cpp` server, or any
/// other OpenAI-compatible endpoint.
struct OpenAICompatibleLanguageProvider: LanguageModelProvider {
    enum Flavor: Sendable {
        case openRouter
        case local
    }

    static let openRouterBaseURL = URL(string: "https://openrouter.ai/api/v1")!

    let baseURL: URL
    let apiKey: String?
    let flavor: Flavor
    let requestTimeout: TimeInterval
    private let session: URLSession

    init(baseURL: URL, apiKey: String?, flavor: Flavor, session: URLSession = .shared, requestTimeout: TimeInterval = 120) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.flavor = flavor
        self.session = session
        self.requestTimeout = requestTimeout
    }

    var isLocal: Bool { flavor == .local && baseURL.isLoopback }

    func models() async throws -> [ModelInfo] {
        var request = URLRequest(url: baseURL.appending(path: "models"), timeoutInterval: 30)
        authorize(&request)
        let (data, response) = try await data(for: request)
        try Self.check(response, data: data, model: nil)
        switch flavor {
        case .openRouter: return try OpenRouterCatalog.parse(data)
        case .local: return try Self.parseLocalModels(data)
        }
    }

    func stream(_ request: LanguageRequest) -> AsyncThrowingStream<LanguageStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeRequest(for: request)
                    let (bytes, response) = try await bytes(for: urlRequest)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes.prefix(8_192) { body.append(byte) }
                        try Self.check(response, data: body, model: request.model)
                    }
                    var parser = ChatCompletionStreamParser()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        for event in try parser.consume(line: line) { continuation.yield(event) }
                        if parser.isDone { break }
                    }
                    for event in parser.finish() { continuation.yield(event) }
                    for event in try parser.completion() { continuation.yield(event) }
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish(throwing: CancellationError())
                } catch let error as URLError where error.code == .timedOut {
                    continuation.finish(throwing: LanguageProviderError.timedOut)
                } catch let error as URLError {
                    continuation.finish(throwing: LanguageProviderError.unreachable(error.localizedDescription))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func makeRequest(for request: LanguageRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appending(path: "chat/completions"), timeoutInterval: requestTimeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        authorize(&urlRequest)
        if flavor == .openRouter {
            urlRequest.setValue("https://github.com/paugarcia32/pulse-notch", forHTTPHeaderField: "HTTP-Referer")
            urlRequest.setValue("Pulse Notch", forHTTPHeaderField: "X-Title")
        }
        var body: [String: Any] = [
            "model": request.model,
            "stream": true,
            "messages": request.messages.map(Self.encode)
        ]
        if !request.tools.isEmpty {
            body["tools"] = try request.tools.map(Self.encode)
            body["tool_choice"] = "auto"
        }
        if let maximum = request.maximumOutputTokens { body["max_tokens"] = maximum }
        if flavor == .openRouter { body["usage"] = ["include": true] }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private func authorize(_ request: inout URLRequest) {
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw Self.map(error)
        }
    }

    private func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        do {
            return try await session.bytes(for: request)
        } catch let error as URLError {
            throw Self.map(error)
        }
    }

    private static func map(_ error: URLError) -> Error {
        switch error.code {
        case .cancelled: CancellationError()
        case .timedOut: LanguageProviderError.timedOut
        default: LanguageProviderError.unreachable(error.localizedDescription)
        }
    }

    static func check(_ response: URLResponse, data: Data, model: String?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        let detail = SystemOneDecisionProvider.errorDetail(from: data)
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw LanguageProviderError.unauthorized
        case 404: throw LanguageProviderError.modelUnavailable(model ?? detail ?? "unknown")
        case 429:
            throw LanguageProviderError.rateLimited(
                retryAfter: http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
            )
        case 400 where detail?.localizedCaseInsensitiveContains("tool") == true:
            throw LanguageProviderError.capabilityMissing(detail ?? "tool calling")
        case 400 where detail?.localizedCaseInsensitiveContains("image") == true:
            throw LanguageProviderError.capabilityMissing(detail ?? "image input")
        default:
            throw LanguageProviderError.streamFailed(detail ?? "HTTP \(http.statusCode)")
        }
    }

    static func encode(_ message: ChatMessage) -> [String: Any] {
        var encoded: [String: Any] = ["role": message.role.rawValue]
        let hasImage = message.content.contains { if case .imagePNG = $0 { true } else { false } }
        if hasImage {
            encoded["content"] = message.content.map { part -> [String: Any] in
                switch part {
                case .text(let text):
                    ["type": "text", "text": text]
                case .imagePNG(let data):
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(data.base64EncodedString())"]]
                }
            }
        } else {
            encoded["content"] = message.text
        }
        if !message.toolCalls.isEmpty {
            encoded["tool_calls"] = message.toolCalls.map { call in
                ["id": call.id, "type": "function", "function": ["name": call.name, "arguments": call.argumentsJSON]]
            }
        }
        if let toolCallID = message.toolCallID { encoded["tool_call_id"] = toolCallID }
        return encoded
    }

    static func encode(_ tool: ToolDefinition) throws -> [String: Any] {
        guard
            let data = tool.parametersSchema.data(using: .utf8),
            let schema = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw LanguageProviderError.malformedResponse("The schema for \(tool.name) is invalid.")
        }
        return ["type": "function", "function": ["name": tool.name, "description": tool.description, "parameters": schema]]
    }

    static func parseLocalModels(_ data: Data) throws -> [ModelInfo] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = root["data"] as? [[String: Any]]
        else {
            throw LanguageProviderError.malformedResponse("The model list is not in the OpenAI format.")
        }
        return models.compactMap { model in
            guard let id = model["id"] as? String else { return nil }
            let meta = model["meta"] as? [String: Any]
            return ModelInfo(
                id: id,
                name: id,
                capabilities: ModelCapabilities(
                    supportsTools: true,
                    supportsVision: false,
                    contextLength: (meta?["n_ctx_train"] as? NSNumber)?.intValue
                )
            )
        }
    }
}

/// Parses OpenRouter's `GET /api/v1/models` catalog.
enum OpenRouterCatalog {
    static func parse(_ data: Data) throws -> [ModelInfo] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = root["data"] as? [[String: Any]]
        else {
            throw LanguageProviderError.malformedResponse("The OpenRouter catalog is not in the expected format.")
        }
        return models.compactMap { model in
            guard let id = model["id"] as? String else { return nil }
            let architecture = model["architecture"] as? [String: Any]
            let inputs = architecture?["input_modalities"] as? [String] ?? []
            let parameters = model["supported_parameters"] as? [String] ?? []
            let pricing = model["pricing"] as? [String: Any]
            return ModelInfo(
                id: id,
                name: model["name"] as? String ?? id,
                capabilities: ModelCapabilities(
                    supportsTools: parameters.contains("tools"),
                    supportsVision: inputs.contains("image"),
                    contextLength: (model["context_length"] as? NSNumber)?.intValue
                ),
                pricing: pricing.map {
                    ModelPricing(prompt: decimal($0["prompt"]), completion: decimal($0["completion"]), image: decimal($0["image"]))
                }
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Keeps the user's selection even when it disappears from a refreshed catalog,
    /// so a catalog update never silently switches models.
    static func merge(_ catalog: [ModelInfo], preserving selectedID: String?) -> [ModelInfo] {
        guard let selectedID, !selectedID.isEmpty, !catalog.contains(where: { $0.id == selectedID }) else { return catalog }
        let manual = ModelInfo(
            id: selectedID,
            name: selectedID,
            capabilities: ModelCapabilities(supportsTools: false, supportsVision: false, contextLength: nil)
        )
        return [manual] + catalog
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        switch value {
        case let string as String: Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
        case let number as NSNumber: number.decimalValue
        default: nil
        }
    }
}
