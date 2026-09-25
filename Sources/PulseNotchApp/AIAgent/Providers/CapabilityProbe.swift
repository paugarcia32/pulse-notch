import CoreGraphics
import Foundation
import ImageIO
import PulseNotchCore
import UniformTypeIdentifiers

struct CapabilityReport: Codable, Hashable, Sendable {
    let modelID: String
    let toolCallsVerified: Bool
    let visionVerified: Bool
    let detail: String

    /// Computer use needs working tool calls; screenshots additionally need vision.
    var readyForComputerUse: Bool { toolCallsVerified }
}

/// Verifies a model's capabilities by exercising them. Successful text generation
/// alone does not mark a model ready for computer use.
struct CapabilityProbe: Sendable {
    let provider: any LanguageModelProvider

    func run(model: String, checkVision: Bool) async -> CapabilityReport {
        var notes: [String] = []
        let tools = await probeToolCalls(model: model)
        notes.append(tools.note)
        var vision = false
        if checkVision {
            let result = await probeVision(model: model)
            vision = result.passed
            notes.append(result.note)
        }
        return CapabilityReport(modelID: model, toolCallsVerified: tools.passed, visionVerified: vision, detail: notes.joined(separator: " "))
    }

    private func probeToolCalls(model: String) async -> (passed: Bool, note: String) {
        let tool = ToolDefinition(
            name: "add_numbers",
            description: "Adds two integers.",
            parametersSchema: #"{"type":"object","properties":{"a":{"type":"integer"},"b":{"type":"integer"}},"required":["a","b"]}"#
        )
        let request = LanguageRequest(
            model: model,
            messages: [
                .system("You are a test harness. Always use the provided tool."),
                .user("Use add_numbers to add 2 and 3.")
            ],
            tools: [tool],
            maximumOutputTokens: 512
        )
        do {
            let response = try await provider.respond(to: request)
            guard let call = response.toolCalls.first(where: { $0.name == "add_numbers" }),
                  let data = call.argumentsJSON.data(using: .utf8),
                  let arguments = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (arguments["a"] as? NSNumber)?.intValue == 2,
                  (arguments["b"] as? NSNumber)?.intValue == 3
            else {
                return (false, "Tool calls: the model did not return the expected structured call.")
            }
            return (true, "Tool calls: verified.")
        } catch let error as LanguageProviderError {
            return (false, "Tool calls: \(error.userMessage)")
        } catch {
            return (false, "Tool calls: \(error.localizedDescription)")
        }
    }

    private func probeVision(model: String) async -> (passed: Bool, note: String) {
        guard let image = Self.solidColorPNG(red: 1, green: 0, blue: 0) else {
            return (false, "Vision: the test image could not be created.")
        }
        let request = LanguageRequest(
            model: model,
            messages: [
                .system("You are a test harness. Answer with a single lowercase word."),
                ChatMessage(role: .user, content: [.text("What color fills this image?"), .imagePNG(image)])
            ],
            maximumOutputTokens: 256
        )
        do {
            let response = try await provider.respond(to: request)
            guard response.text.lowercased().contains("red") else {
                return (false, "Vision: the model did not identify the test image.")
            }
            return (true, "Vision: verified.")
        } catch let error as LanguageProviderError {
            return (false, "Vision: \(error.userMessage)")
        } catch {
            return (false, "Vision: \(error.localizedDescription)")
        }
    }

    static func solidColorPNG(red: CGFloat, green: CGFloat, blue: CGFloat, size: Int = 64) -> Data? {
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
