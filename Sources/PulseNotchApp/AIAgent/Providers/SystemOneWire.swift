import Foundation
import PulseNotchCore

/// Encodes and decodes the System One wire format shared by TypeSafe's JEV API,
/// `laya-serve`, and the managed Laya helper.
enum SystemOneWire {
    static func body(for request: DecisionRequest, model: String) throws -> [String: Any] {
        var questions: [String: Any] = [:]
        for question in request.questions {
            guard question.isWellFormed else {
                throw DecisionProviderError.malformedResponse("Question “\(question.id)” is not well formed.")
            }
            var encoded: [String: Any] = ["instructions": question.instructions]
            switch question.kind {
            case .choice(let options):
                encoded["type"] = "choice"
                var criteria: [String: Any] = [:]
                for option in options { criteria[option.value] = option.description ?? NSNull() }
                encoded["criteria"] = criteria
            case .score(let levels):
                encoded["type"] = "score"
                encoded["criteria"] = levels
            case .noul(let whenTrue, let whenFalse):
                encoded["type"] = "noul"
                if whenTrue != nil || whenFalse != nil {
                    encoded["criteria"] = ["true": whenTrue ?? "yes", "false": whenFalse ?? "no"]
                }
            }
            questions[question.id] = encoded
        }
        return ["state": stateValue(request.state), "model": model, "questions": questions]
    }

    static func encode(_ request: DecisionRequest, model: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: body(for: request, model: model), options: [.sortedKeys])
    }

    /// Decodes the `answers` object of a System One response, validating each answer
    /// against the question that was asked.
    static func decodeAnswers(
        _ object: Any,
        for request: DecisionRequest
    ) throws -> (answers: [String: DecisionAnswer], model: String?, inputTokens: Int?) {
        guard let root = object as? [String: Any], let answers = root["answers"] as? [String: Any] else {
            throw DecisionProviderError.malformedResponse("The response has no answers.")
        }
        var decoded: [String: DecisionAnswer] = [:]
        for question in request.questions {
            guard let answer = answers[question.id] as? [String: Any] else {
                throw DecisionProviderError.malformedResponse("Missing answer for “\(question.id)”.")
            }
            let confidence = (answer["confidence"] as? NSNumber)?.doubleValue
            switch question.kind {
            case .choice(let options):
                guard let selected = answer["choice"] as? String else {
                    throw DecisionProviderError.malformedResponse("Answer “\(question.id)” has no choice.")
                }
                let probabilities = (answer["probabilities"] as? [String: Any] ?? [:])
                    .compactMapValues { ($0 as? NSNumber)?.doubleValue }
                decoded[question.id] = try DecisionAnswer.normalizedChoice(
                    selected: selected,
                    probabilities: probabilities,
                    confidence: confidence,
                    options: options
                )
            case .score(let levels):
                guard let score = (answer["score"] as? NSNumber)?.doubleValue else {
                    throw DecisionProviderError.malformedResponse("Answer “\(question.id)” has no score.")
                }
                decoded[question.id] = try DecisionAnswer.normalizedScore(value: score, levelCount: levels.count, confidence: confidence)
            case .noul:
                guard let probability = (answer["noul"] as? NSNumber)?.doubleValue else {
                    throw DecisionProviderError.malformedResponse("Answer “\(question.id)” has no probability.")
                }
                decoded[question.id] = try DecisionAnswer.normalizedNoul(probabilityYes: probability, confidence: confidence)
            }
        }
        let usage = root["usage"] as? [String: Any]
        return (decoded, root["model"] as? String, (usage?["input_tokens"] as? NSNumber)?.intValue)
    }

    /// Sends the state as a JSON object when it parses as one, which both JEV and
    /// Laya accept, and as a string otherwise.
    private static func stateValue(_ state: String) -> Any {
        guard
            let data = state.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            object is [String: Any] || object is [Any]
        else { return state }
        return object
    }
}
