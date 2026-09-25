import Foundation

public struct DecisionOption: Codable, Hashable, Sendable {
    public let value: String
    public let description: String?

    public init(_ value: String, description: String? = nil) {
        self.value = value
        self.description = description
    }
}

public enum DecisionQuestionKind: Codable, Hashable, Sendable {
    /// Select exactly one option.
    case choice([DecisionOption])
    /// Rate on an ordered scale from the first (lowest) to the last level.
    case score(levels: [String])
    /// A yes/no question answered with the probability of yes.
    case noul(whenTrue: String?, whenFalse: String?)
}

public struct DecisionQuestion: Codable, Hashable, Sendable, Identifiable {
    public static let maximumChoiceOptions = 255
    public static let scoreLevelRange = 2...10

    public let id: String
    public let instructions: String
    public let kind: DecisionQuestionKind

    public init(id: String, instructions: String, kind: DecisionQuestionKind) {
        self.id = id
        self.instructions = instructions
        self.kind = kind
    }

    public var isWellFormed: Bool {
        switch kind {
        case .choice(let options):
            !options.isEmpty
                && options.count <= Self.maximumChoiceOptions
                && Set(options.map(\.value)).count == options.count
        case .score(let levels):
            Self.scoreLevelRange.contains(levels.count)
        case .noul:
            true
        }
    }
}

public struct DecisionRequest: Hashable, Sendable {
    /// Compact, bounded task state serialized as JSON text.
    public let state: String
    public let questions: [DecisionQuestion]

    public init(state: String, questions: [DecisionQuestion]) {
        self.state = state
        self.questions = questions
    }
}

public enum DecisionAnswer: Hashable, Sendable {
    case choice(selected: String, probabilities: [String: Double], confidence: Double)
    /// `value` is the probability-weighted level index and may fall between levels.
    case score(value: Double, level: Int, confidence: Double)
    case noul(probabilityYes: Double, confidence: Double)

    public var confidence: Double {
        switch self {
        case .choice(_, _, let confidence), .score(_, _, let confidence), .noul(_, let confidence):
            confidence
        }
    }

    public var selectedOption: String? {
        if case .choice(let selected, _, _) = self { return selected }
        return nil
    }

    public var probabilityYes: Double? {
        if case .noul(let probability, _) = self { return probability }
        return nil
    }

    public var scoreLevel: Int? {
        if case .score(_, let level, _) = self { return level }
        return nil
    }

    /// Normalizes a choice answer. Providers that omit a confidence report the
    /// probability of the selected option instead.
    public static func normalizedChoice(
        selected: String,
        probabilities: [String: Double],
        confidence: Double?,
        options: [DecisionOption]
    ) throws -> DecisionAnswer {
        guard options.contains(where: { $0.value == selected }) else {
            throw DecisionProviderError.malformedResponse("Choice “\(selected)” is not one of the offered options.")
        }
        let clamped = probabilities.mapValues(clampProbability)
        return .choice(
            selected: selected,
            probabilities: clamped,
            confidence: clampProbability(confidence ?? clamped[selected] ?? 0)
        )
    }

    public static func normalizedScore(value: Double, levelCount: Int, confidence: Double?) throws -> DecisionAnswer {
        guard value.isFinite, levelCount >= 2 else {
            throw DecisionProviderError.malformedResponse("Score answer is not a finite level index.")
        }
        let bounded = min(max(value, 0), Double(levelCount - 1))
        let level = Int(bounded.rounded())
        let distance = abs(bounded - Double(level))
        return .score(
            value: bounded,
            level: level,
            confidence: clampProbability(confidence ?? (1 - distance))
        )
    }

    /// JEV reports only the probability of yes; Laya also reports a confidence.
    public static func normalizedNoul(probabilityYes: Double, confidence: Double?) throws -> DecisionAnswer {
        guard probabilityYes.isFinite else {
            throw DecisionProviderError.malformedResponse("Yes/no answer is not a probability.")
        }
        let probability = clampProbability(probabilityYes)
        return .noul(
            probabilityYes: probability,
            confidence: clampProbability(confidence ?? max(probability, 1 - probability))
        )
    }

    private static func clampProbability(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

public struct DecisionProviderMetadata: Hashable, Sendable {
    public let provider: String
    public let model: String
    public let isLocal: Bool
    public let inputTokens: Int?

    public init(provider: String, model: String, isLocal: Bool, inputTokens: Int? = nil) {
        self.provider = provider
        self.model = model
        self.isLocal = isLocal
        self.inputTokens = inputTokens
    }
}

public struct DecisionResponse: Hashable, Sendable {
    public let answers: [String: DecisionAnswer]
    public let metadata: DecisionProviderMetadata

    public init(answers: [String: DecisionAnswer], metadata: DecisionProviderMetadata) {
        self.answers = answers
        self.metadata = metadata
    }

    public func answer(_ id: String) throws -> DecisionAnswer {
        guard let answer = answers[id] else {
            throw DecisionProviderError.malformedResponse("The decision provider did not answer “\(id)”.")
        }
        return answer
    }
}

public enum DecisionProviderError: Error, Hashable, Sendable {
    case missingCredential
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case unavailable(String)
    case malformedResponse(String)
    case contextLimitExceeded(estimatedTokens: Int, limit: Int)
    case timedOut

    public var userMessage: String {
        switch self {
        case .missingCredential: "Add an API key for the decision provider in AI Agent settings."
        case .unauthorized: "The decision provider rejected the API key."
        case .rateLimited: "The decision provider is rate limiting requests. Try again shortly."
        case .unavailable(let detail): "The decision provider is unavailable: \(detail)"
        case .malformedResponse(let detail): "The decision provider returned an unexpected answer: \(detail)"
        case .contextLimitExceeded(let tokens, let limit):
            "The task state needs about \(tokens) tokens, more than the decision model's \(limit)-token limit."
        case .timedOut: "The decision provider did not respond in time."
        }
    }
}

public protocol DecisionProvider: Sendable {
    /// Maximum tokens accepted for the state plus the longest question.
    var contextLimit: Int { get }
    var metadata: DecisionProviderMetadata { get }
    func decide(_ request: DecisionRequest) async throws -> DecisionResponse
}
