import Foundation

public enum ChatRole: String, Codable, Hashable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public enum ChatContent: Hashable, Sendable {
    case text(String)
    /// An ephemeral PNG screenshot. It is sent to the model but never persisted.
    case imagePNG(Data)
}

public struct ToolCall: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public struct ChatMessage: Hashable, Sendable {
    public let role: ChatRole
    public let content: [ChatContent]
    public let toolCalls: [ToolCall]
    public let toolCallID: String?

    public init(role: ChatRole, content: [ChatContent], toolCalls: [ToolCall] = [], toolCallID: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    public static func system(_ text: String) -> ChatMessage { ChatMessage(role: .system, content: [.text(text)]) }
    public static func user(_ text: String) -> ChatMessage { ChatMessage(role: .user, content: [.text(text)]) }
    public static func assistant(_ text: String, toolCalls: [ToolCall] = []) -> ChatMessage {
        ChatMessage(role: .assistant, content: text.isEmpty ? [] : [.text(text)], toolCalls: toolCalls)
    }
    public static func toolResult(_ text: String, for callID: String, image: Data? = nil) -> ChatMessage {
        ChatMessage(role: .tool, content: [.text(text)] + (image.map { [.imagePNG($0)] } ?? []), toolCallID: callID)
    }

    public var text: String {
        content.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined()
    }
}

public struct ToolDefinition: Hashable, Sendable {
    public let name: String
    public let description: String
    /// JSON Schema for the arguments object.
    public let parametersSchema: String

    public init(name: String, description: String, parametersSchema: String) {
        self.name = name
        self.description = description
        self.parametersSchema = parametersSchema
    }
}

public struct ModelCapabilities: Codable, Hashable, Sendable {
    public var supportsTools: Bool
    public var supportsVision: Bool
    public var contextLength: Int?

    public init(supportsTools: Bool, supportsVision: Bool, contextLength: Int?) {
        self.supportsTools = supportsTools
        self.supportsVision = supportsVision
        self.contextLength = contextLength
    }
}

/// Prices in US dollars per token, as published by the provider.
public struct ModelPricing: Codable, Hashable, Sendable {
    public var prompt: Decimal?
    public var completion: Decimal?
    public var image: Decimal?

    public init(prompt: Decimal?, completion: Decimal?, image: Decimal? = nil) {
        self.prompt = prompt
        self.completion = completion
        self.image = image
    }
}

public struct ModelInfo: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let capabilities: ModelCapabilities
    public let pricing: ModelPricing?

    public init(id: String, name: String, capabilities: ModelCapabilities, pricing: ModelPricing? = nil) {
        self.id = id
        self.name = name
        self.capabilities = capabilities
        self.pricing = pricing
    }
}

public struct LanguageRequest: Hashable, Sendable {
    public let model: String
    public let messages: [ChatMessage]
    public let tools: [ToolDefinition]
    public let maximumOutputTokens: Int?

    public init(model: String, messages: [ChatMessage], tools: [ToolDefinition] = [], maximumOutputTokens: Int? = nil) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.maximumOutputTokens = maximumOutputTokens
    }
}

public enum FinishReason: Hashable, Sendable {
    case stop
    case toolCalls
    case length
    case other(String)
}

public struct TokenUsage: Hashable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public enum LanguageStreamEvent: Hashable, Sendable {
    case textDelta(String)
    case toolCalls([ToolCall])
    case finished(FinishReason, TokenUsage?)
}

public enum LanguageProviderError: Error, Hashable, Sendable {
    case missingCredential
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case modelUnavailable(String)
    case capabilityMissing(String)
    case malformedResponse(String)
    case streamFailed(String)
    case timedOut
    case unreachable(String)

    public var userMessage: String {
        switch self {
        case .missingCredential: "Add an API key for the language model in AI Agent settings."
        case .unauthorized: "The language model provider rejected the API key."
        case .rateLimited: "The language model provider is rate limiting requests. Try again shortly."
        case .modelUnavailable(let model): "The model “\(model)” is not available from this provider."
        case .capabilityMissing(let detail): "The selected model cannot do this: \(detail)"
        case .malformedResponse(let detail): "The language model returned an unexpected response: \(detail)"
        case .streamFailed(let detail): "The response stream failed: \(detail)"
        case .timedOut: "The language model did not respond in time."
        case .unreachable(let detail): "The language model server is unreachable: \(detail)"
        }
    }
}

public protocol LanguageModelProvider: Sendable {
    var isLocal: Bool { get }
    func models() async throws -> [ModelInfo]
    /// Streams one assistant turn. Cancelling the consuming task cancels inference.
    func stream(_ request: LanguageRequest) -> AsyncThrowingStream<LanguageStreamEvent, Error>
}

public struct LanguageResponse: Hashable, Sendable {
    public var text: String
    public var toolCalls: [ToolCall]
    public var finishReason: FinishReason?
    public var usage: TokenUsage?

    public init(text: String = "", toolCalls: [ToolCall] = [], finishReason: FinishReason? = nil, usage: TokenUsage? = nil) {
        self.text = text
        self.toolCalls = toolCalls
        self.finishReason = finishReason
        self.usage = usage
    }
}

extension LanguageModelProvider {
    /// Consumes one streamed turn, forwarding text as it arrives.
    public func respond(
        to request: LanguageRequest,
        onText: @Sendable (String) -> Void = { _ in }
    ) async throws -> LanguageResponse {
        var response = LanguageResponse()
        for try await event in stream(request) {
            try Task.checkCancellation()
            switch event {
            case .textDelta(let text):
                response.text += text
                onText(text)
            case .toolCalls(let calls):
                response.toolCalls += calls
            case .finished(let reason, let usage):
                response.finishReason = reason
                response.usage = usage ?? response.usage
            }
        }
        try Task.checkCancellation()
        return response
    }
}

/// Reassembles tool calls whose identifiers, names, and JSON arguments arrive in
/// fragments across streamed deltas, keyed by the provider's per-call index.
public struct ToolCallAccumulator: Sendable {
    private struct Partial: Sendable {
        var id: String?
        var name: String?
        var arguments = ""
    }

    private var partials: [Int: Partial] = [:]

    public init() {}

    public var isEmpty: Bool { partials.isEmpty }

    public mutating func append(index: Int, id: String?, name: String?, argumentsFragment: String?) {
        var partial = partials[index] ?? Partial()
        if let id, !id.isEmpty { partial.id = id }
        if let name, !name.isEmpty { partial.name = (partial.name ?? "") == name ? name : (partial.name ?? "") + name }
        if let argumentsFragment { partial.arguments += argumentsFragment }
        partials[index] = partial
    }

    /// Returns the calls in index order, validating that every call has a name and
    /// that its arguments form a JSON object.
    public func completedCalls() throws -> [ToolCall] {
        try partials.sorted { $0.key < $1.key }.map { index, partial in
            guard let name = partial.name, !name.isEmpty else {
                throw LanguageProviderError.malformedResponse("A tool call is missing its name.")
            }
            let arguments = partial.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = arguments.isEmpty ? "{}" : arguments
            guard
                let data = normalized.data(using: .utf8),
                (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
            else {
                throw LanguageProviderError.malformedResponse("Arguments for “\(name)” are not a JSON object.")
            }
            return ToolCall(id: partial.id ?? "call_\(index)", name: name, argumentsJSON: normalized)
        }
    }
}
