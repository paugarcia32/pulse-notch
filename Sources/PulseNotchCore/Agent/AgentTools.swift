import Foundation

/// A parsed tool call from the language model. The language model directs the work in
/// natural-language steps; the decision provider chooses the concrete actions.
public enum AgentToolInvocation: Hashable, Sendable {
    case observe
    case captureScreen
    case openApplication(name: String)
    case openURL(URL)
    /// One desktop step for the decision provider to carry out, with any text to type.
    case operate(step: String, text: String?)
    case finish(summary: String, evidence: String)
    case askUser(String)
}

public enum AgentToolError: Error, Hashable, Sendable {
    case unknownTool(String)
    case invalidArguments(tool: String, detail: String)

    public var message: String {
        switch self {
        case .unknownTool(let name): "Unknown tool “\(name)”."
        case .invalidArguments(let tool, let detail): "Invalid arguments for \(tool): \(detail)"
        }
    }
}

public enum AgentTools {
    public static func definitions(computerUse: Bool, vision: Bool) -> [ToolDefinition] {
        var tools: [ToolDefinition] = []
        if computerUse {
            tools += [
                ToolDefinition(
                    name: "operate",
                    description: "Carry out one concrete desktop step, such as “click the Save button” or “type the text into the document body”. The decision model chooses and performs the actions on screen until the step is done. When the step involves typing, `text` is required and holds the exact characters to type.",
                    parametersSchema: #"{"type":"object","properties":{"step":{"type":"string"},"text":{"type":"string"}},"required":["step"],"additionalProperties":false}"#
                ),
                ToolDefinition(
                    name: "open_app",
                    description: "Open or activate an application by name, for example “Safari” or “TextEdit”.",
                    parametersSchema: #"{"type":"object","properties":{"name":{"type":"string"}},"required":["name"],"additionalProperties":false}"#
                ),
                ToolDefinition(
                    name: "open_url",
                    description: "Open an http or https URL in the default browser.",
                    parametersSchema: #"{"type":"object","properties":{"url":{"type":"string"}},"required":["url"],"additionalProperties":false}"#
                ),
                ToolDefinition(
                    name: "observe_screen",
                    description: "Describe the frontmost window and its visible controls.",
                    parametersSchema: #"{"type":"object","properties":{},"additionalProperties":false}"#
                )
            ]
            if vision {
                tools.append(ToolDefinition(
                    name: "capture_screen",
                    description: "Take a screenshot to check whether the work is on track.",
                    parametersSchema: #"{"type":"object","properties":{},"additionalProperties":false}"#
                ))
            }
        }
        tools += [
            ToolDefinition(
                name: "finish_task",
                description: "Finish the task. Summarize the result and cite the observed evidence that it is complete.",
                parametersSchema: #"{"type":"object","properties":{"summary":{"type":"string"},"evidence":{"type":"string"}},"required":["summary","evidence"],"additionalProperties":false}"#
            ),
            ToolDefinition(
                name: "ask_user",
                description: "Ask the user for help when the instruction is ambiguous, the work is not going as expected, or authorization or information is missing.",
                parametersSchema: #"{"type":"object","properties":{"question":{"type":"string"}},"required":["question"],"additionalProperties":false}"#
            )
        ]
        return tools
    }

    public static func parse(_ call: ToolCall) throws -> AgentToolInvocation {
        guard
            let data = call.argumentsJSON.data(using: .utf8),
            let arguments = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            throw AgentToolError.invalidArguments(tool: call.name, detail: "arguments are not a JSON object")
        }
        func string(_ key: String) -> String? {
            (arguments[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        func required(_ key: String) throws -> String {
            guard let value = string(key) else {
                throw AgentToolError.invalidArguments(tool: call.name, detail: "missing “\(key)”")
            }
            return value
        }

        switch call.name {
        case "operate":
            let text = (arguments["text"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .operate(step: try required("step"), text: text)
        case "observe_screen":
            return .observe
        case "capture_screen":
            return .captureScreen
        case "open_app":
            return .openApplication(name: try required("name"))
        case "open_url":
            let text = try required("url")
            guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
                throw AgentToolError.invalidArguments(tool: call.name, detail: "only http and https URLs can be opened")
            }
            return .openURL(url)
        case "finish_task":
            return .finish(summary: try required("summary"), evidence: string("evidence") ?? "")
        case "ask_user":
            return .askUser(try required("question"))
        default:
            throw AgentToolError.unknownTool(call.name)
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
