import Foundation
import PulseNotchCore

/// Parses OpenAI-compatible chat-completion server-sent events line by line.
///
/// OpenRouter and `llama.cpp` both send one JSON chunk per `data:` line, comment
/// lines beginning with `:` as keep-alives, and a final `data: [DONE]`. Errors can
/// arrive mid-stream with HTTP 200, and tool-call arguments arrive in fragments.
struct ChatCompletionStreamParser {
    private(set) var isDone = false
    private var accumulator = ToolCallAccumulator()
    private var finishReason: FinishReason?
    private var usage: TokenUsage?
    private var thinkFilter = ThinkTagFilter()

    /// Returns the events produced by one line of the stream.
    mutating func consume(line rawLine: String) throws -> [LanguageStreamEvent] {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isDone, !line.isEmpty, !line.hasPrefix(":") else { return [] }
        guard line.hasPrefix("data:") else { return [] }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return finish() }

        guard
            let data = payload.data(using: .utf8),
            let chunk = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw LanguageProviderError.malformedResponse("A streamed chunk is not valid JSON.")
        }
        if let error = chunk["error"] as? [String: Any] {
            throw LanguageProviderError.streamFailed(error["message"] as? String ?? "The provider reported an error.")
        }
        if let usage = chunk["usage"] as? [String: Any] {
            self.usage = TokenUsage(
                inputTokens: (usage["prompt_tokens"] as? NSNumber)?.intValue ?? 0,
                outputTokens: (usage["completion_tokens"] as? NSNumber)?.intValue ?? 0
            )
        }

        var events: [LanguageStreamEvent] = []
        for choice in chunk["choices"] as? [[String: Any]] ?? [] {
            let delta = choice["delta"] as? [String: Any] ?? [:]
            if let content = delta["content"] as? String, !content.isEmpty {
                let visible = thinkFilter.filter(content)
                if !visible.isEmpty { events.append(.textDelta(visible)) }
            }
            for call in delta["tool_calls"] as? [[String: Any]] ?? [] {
                let function = call["function"] as? [String: Any]
                accumulator.append(
                    index: (call["index"] as? NSNumber)?.intValue ?? 0,
                    id: call["id"] as? String,
                    name: function?["name"] as? String,
                    argumentsFragment: function?["arguments"] as? String
                )
            }
            if let reason = choice["finish_reason"] as? String {
                if reason == "error" {
                    throw LanguageProviderError.streamFailed("The provider ended the response with an error.")
                }
                finishReason = Self.finishReason(reason)
            }
        }
        return events
    }

    /// Completes the stream when the connection closes, with or without `[DONE]`.
    mutating func finish() -> [LanguageStreamEvent] {
        guard !isDone else { return [] }
        isDone = true
        var events: [LanguageStreamEvent] = []
        let trailing = thinkFilter.flush()
        if !trailing.isEmpty { events.append(.textDelta(trailing)) }
        return events
    }

    /// The reassembled tool calls and finish reason, validated once the stream ends.
    func completion() throws -> [LanguageStreamEvent] {
        var events: [LanguageStreamEvent] = []
        if !accumulator.isEmpty { events.append(.toolCalls(try accumulator.completedCalls())) }
        let reason = finishReason ?? (accumulator.isEmpty ? .stop : .toolCalls)
        events.append(.finished(reason, usage))
        return events
    }

    private static func finishReason(_ value: String) -> FinishReason {
        switch value {
        case "stop": .stop
        case "tool_calls", "function_call": .toolCalls
        case "length": .length
        default: .other(value)
        }
    }
}

/// Removes `<think>…</think>` reasoning blocks that some local chat templates emit
/// in the content channel, even when a block spans several deltas.
struct ThinkTagFilter {
    private static let open = "<think>"
    private static let close = "</think>"
    private var buffer = ""
    private var insideThink = false

    mutating func filter(_ text: String) -> String {
        buffer += text
        var output = ""
        while true {
            if insideThink {
                guard let end = buffer.range(of: Self.close) else {
                    buffer = String(buffer.suffix(Self.close.count - 1))
                    return output
                }
                buffer = String(buffer[end.upperBound...])
                insideThink = false
            } else if let start = buffer.range(of: Self.open) {
                output += buffer[..<start.lowerBound]
                buffer = String(buffer[start.upperBound...])
                insideThink = true
            } else {
                // Hold back a possible partial "<think>" at the end of the chunk.
                let keep = Self.partialPrefixLength(of: buffer)
                output += buffer.dropLast(keep)
                buffer = String(buffer.suffix(keep))
                return output
            }
        }
    }

    mutating func flush() -> String {
        defer { buffer = "" }
        return insideThink ? "" : buffer
    }

    private static func partialPrefixLength(of text: String) -> Int {
        for length in stride(from: min(open.count - 1, text.count), to: 0, by: -1)
        where open.hasPrefix(text.suffix(length)) {
            return length
        }
        return 0
    }
}
