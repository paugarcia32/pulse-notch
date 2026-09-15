import IOKit.graphics
import Foundation
import PulseNotchCore

struct DisplayBrightnessProvider: DisplayBrightnessProviding {
    func currentDisplayBrightness() async throws -> DisplayBrightnessStatus {
        if let brightness = readIODisplayBrightness() {
            return DisplayBrightnessStatus(level: Int((brightness * 100).rounded()))
        }

        return try await Task.detached(priority: .utility) {
            try readBuiltInDisplayBrightness()
        }.value
    }

    private func readIODisplayBrightness() -> Float? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var brightness: Float = 0
        guard IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness) == kIOReturnSuccess else { return nil }
        return brightness
    }
}

private func readBuiltInDisplayBrightness() throws -> DisplayBrightnessStatus {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/libexec/corebrightnessdiag")
    process.arguments = ["status-info"]

    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0,
          let status = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let displays = status["CBDisplays"] as? [String: Any]
    else { throw CocoaError(.fileReadUnknown) }

    for value in displays.values {
        guard let display = value as? [String: Any],
              let details = display["Display"] as? [String: Any],
              details["DisplayServicesIsBuiltInDisplay"] as? Bool == true,
              let brightness = details["DisplayServicesBrightness"] as? NSNumber
        else { continue }

        return DisplayBrightnessStatus(level: Int((brightness.floatValue * 100).rounded()))
    }

    throw CocoaError(.fileReadUnknown)
}
