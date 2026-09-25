import Foundation

public enum TokenEstimator {
    /// A deliberately conservative estimate (about three UTF-8 bytes per token) so
    /// multilingual text does not overrun small encoder context windows.
    public static func estimate(_ text: String) -> Int {
        (text.utf8.count + 2) / 3
    }

    public static func estimate(_ question: DecisionQuestion) -> Int {
        var total = estimate(question.instructions) + 8
        switch question.kind {
        case .choice(let options):
            total += options.reduce(0) { $0 + estimate($1.value) + estimate($1.description ?? "") + 2 }
        case .score(let levels):
            total += levels.reduce(0) { $0 + estimate($1) + 2 }
        case .noul(let whenTrue, let whenFalse):
            total += estimate(whenTrue ?? "") + estimate(whenFalse ?? "")
        }
        return total
    }
}

/// Orders controls by relevance to the task so the most useful ones survive when a
/// decision model's context is small. Secure fields are never included.
public enum ElementShortlist {
    public static func ranked(
        _ elements: [AccessibleElement],
        relevantTo text: String,
        pinned: Set<String> = []
    ) -> [AccessibleElement] {
        let terms = words(in: text)
        return elements.enumerated()
            .filter { !$0.element.isSecure && !$0.element.label.isEmpty }
            .map { offset, element -> (AccessibleElement, Int, Int) in
                let elementTerms = words(in: "\(element.label) \(element.value ?? "") \(element.role)")
                var score = terms.intersection(elementTerms).count * 10
                if pinned.contains(element.id) { score += 10_000 }
                if element.isEnabled { score += 1 }
                if !element.actions.isEmpty { score += 1 }
                return (element, score, offset)
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }

    static func words(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 }
        )
    }
}

public enum DecisionStateFit: Hashable, Sendable {
    case fits(DecisionRequest, candidates: [AccessibleElement], omitted: Int)
    /// Decisive information does not fit the decision model's context.
    case insufficientContext(String)
}

/// Builds decision requests that respect a provider's context limit, reporting
/// insufficient context instead of silently dropping decisive information.
public struct DecisionStateBudget: Sendable {
    public let limit: Int
    public let maximumCandidates: Int

    public init(limit: Int, maximumCandidates: Int = 60) {
        self.limit = limit
        self.maximumCandidates = maximumCandidates
    }

    /// - Parameters:
    ///   - baseState: Fields that must always be present, such as the instruction.
    ///   - candidates: Controls ordered by relevance; the first `requiredCount` are decisive.
    ///   - makeQuestions: Builds the questions for the included candidates.
    public func fit(
        baseState: [String: String],
        candidates: [AccessibleElement],
        requiredCount: Int,
        makeQuestions: ([AccessibleElement]) -> [DecisionQuestion]
    ) -> DecisionStateFit {
        let required = min(requiredCount, candidates.count)
        var count = min(candidates.count, maximumCandidates)
        while count >= required {
            let included = Array(candidates.prefix(count))
            let state = Self.encodeState(baseState, candidates: included)
            let questions = makeQuestions(included)
            let longestQuestion = questions.map(TokenEstimator.estimate).max() ?? 0
            if TokenEstimator.estimate(state) + longestQuestion <= limit {
                return .fits(
                    DecisionRequest(state: state, questions: questions),
                    candidates: included,
                    omitted: candidates.count - count
                )
            }
            if count == 0 { break }
            count -= 1
        }
        let minimal = Self.encodeState(baseState, candidates: Array(candidates.prefix(required)))
        let longest = makeQuestions(Array(candidates.prefix(required))).map(TokenEstimator.estimate).max() ?? 0
        return .insufficientContext(
            "The decision needs about \(TokenEstimator.estimate(minimal) + longest) tokens, but the decision model accepts \(limit)."
        )
    }

    static func encodeState(_ base: [String: String], candidates: [AccessibleElement]) -> String {
        var object: [String: Any] = base
        if !candidates.isEmpty {
            object["controls"] = candidates.map { element -> [String: String] in
                var entry = ["id": element.id, "role": element.role, "label": element.label]
                if let value = element.value, !value.isEmpty { entry["value"] = String(value.prefix(120)) }
                if !element.isEnabled { entry["enabled"] = "no" }
                return entry
            }
        }
        guard
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}
