import Foundation

/// A parsed tool call from the language model, before targets are resolved
/// against a fresh observation.
public enum AgentToolInvocation: Hashable, Sendable {
    case observe
    case captureScreen
    case openApplication(name: String)
    case openURL(URL)
    case click(elementID: String?, imagePoint: ImagePoint?)
    case typeText(String, elementID: String?)
    case pressKeys(KeyShortcut)
    case scroll(ScrollDirection, amount: Int, elementID: String?)
    case finish(summary: String, evidence: String)
    case askUser(String)

    public var requiresDesktop: Bool {
        switch self {
        case .finish, .askUser: false
        default: true
        }
    }
}

/// A point in the most recent screenshot's pixel space.
public struct ImagePoint: Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
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
                    name: "observe_screen",
                    description: "List the accessible controls in the frontmost window. Use element ids from the latest observation only.",
                    parametersSchema: #"{"type":"object","properties":{},"additionalProperties":false}"#
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
                    name: "click",
                    description: vision
                        ? "Click a control by element_id. Only when no element fits, pass x and y in pixels of the latest screenshot."
                        : "Click a control by element_id from the latest observation.",
                    parametersSchema: vision
                        ? #"{"type":"object","properties":{"element_id":{"type":"string"},"x":{"type":"number"},"y":{"type":"number"}},"additionalProperties":false}"#
                        : #"{"type":"object","properties":{"element_id":{"type":"string"}},"required":["element_id"],"additionalProperties":false}"#
                ),
                ToolDefinition(
                    name: "type_text",
                    description: "Type text, optionally into the control with element_id (it is focused first).",
                    parametersSchema: #"{"type":"object","properties":{"text":{"type":"string"},"element_id":{"type":"string"}},"required":["text"],"additionalProperties":false}"#
                ),
                ToolDefinition(
                    name: "press_keys",
                    description: "Press a key or shortcut such as “return”, “tab”, “cmd+l”, or “cmd+shift+t”.",
                    parametersSchema: #"{"type":"object","properties":{"keys":{"type":"string"}},"required":["keys"],"additionalProperties":false}"#
                ),
                ToolDefinition(
                    name: "scroll",
                    description: "Scroll the frontmost window or the control with element_id.",
                    parametersSchema: #"{"type":"object","properties":{"direction":{"type":"string","enum":["up","down","left","right"]},"amount":{"type":"integer","minimum":1,"maximum":20},"element_id":{"type":"string"}},"required":["direction"],"additionalProperties":false}"#
                )
            ]
            if vision {
                tools.append(ToolDefinition(
                    name: "capture_screen",
                    description: "Capture a screenshot of the display with the frontmost window when accessible controls are not enough.",
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
                description: "Ask the user a question when the instruction is ambiguous, or authorization or information is missing.",
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
        func number(_ key: String) -> Double? {
            (arguments[key] as? NSNumber)?.doubleValue
        }

        switch call.name {
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
        case "click":
            let elementID = string("element_id")
            let point = number("x").flatMap { x in number("y").map { ImagePoint(x: x, y: $0) } }
            guard elementID != nil || point != nil else {
                throw AgentToolError.invalidArguments(tool: call.name, detail: "pass element_id, or x and y")
            }
            return .click(elementID: elementID, imagePoint: elementID == nil ? point : nil)
        case "type_text":
            guard let text = arguments["text"] as? String, !text.isEmpty else {
                throw AgentToolError.invalidArguments(tool: call.name, detail: "missing “text”")
            }
            return .typeText(text, elementID: string("element_id"))
        case "press_keys":
            return .pressKeys(try parseShortcut(try required("keys"), tool: call.name))
        case "scroll":
            guard let direction = ScrollDirection(rawValue: try required("direction").lowercased()) else {
                throw AgentToolError.invalidArguments(tool: call.name, detail: "direction must be up, down, left, or right")
            }
            let amount = min(max(Int(number("amount") ?? 3), 1), 20)
            return .scroll(direction, amount: amount, elementID: string("element_id"))
        case "finish_task":
            return .finish(summary: try required("summary"), evidence: string("evidence") ?? "")
        case "ask_user":
            return .askUser(try required("question"))
        default:
            throw AgentToolError.unknownTool(call.name)
        }
    }

    static func parseShortcut(_ text: String, tool: String) throws -> KeyShortcut {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.last, !key.isEmpty else {
            throw AgentToolError.invalidArguments(tool: tool, detail: "missing key")
        }
        var modifiers: Set<KeyModifier> = []
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command", "⌘": modifiers.insert(.command)
            case "opt", "option", "alt", "⌥": modifiers.insert(.option)
            case "ctrl", "control", "⌃": modifiers.insert(.control)
            case "shift", "⇧": modifiers.insert(.shift)
            default: throw AgentToolError.invalidArguments(tool: tool, detail: "unknown modifier “\(part)”")
            }
        }
        return KeyShortcut(key: key, modifiers: modifiers)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
