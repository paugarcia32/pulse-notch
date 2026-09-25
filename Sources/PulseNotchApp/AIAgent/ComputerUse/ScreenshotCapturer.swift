import CoreGraphics
import Foundation
import ImageIO
import PulseNotchCore
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Captures one display, excluding Pulse Notch's own windows. Images stay in memory.
enum ScreenshotCapturer {
    static func capture(displayID: UInt32?, layout: DisplayLayout, excludingProcessID: pid_t) async throws -> ScreenCapture {
        guard CGPreflightScreenCaptureAccess() else { throw ComputerUseError.screenRecordingPermissionMissing }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw mapped(error)
        }
        let requestedID = displayID ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == requestedID })
            ?? content.displays.first(where: { $0.displayID == CGMainDisplayID() })
            ?? content.displays.first else {
            throw ComputerUseError.targetUnavailable("No display is available to capture.")
        }
        let excluded = content.applications.filter { $0.processID == excludingProcessID }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        let snapshot = layout.display(withID: display.displayID)
        let frame = snapshot?.frame ?? ScreenRect(CGDisplayBounds(display.displayID))
        let size = ScreenshotScaling.pixelSize(
            pointWidth: frame.width,
            pointHeight: frame.height,
            backingScale: snapshot?.backingScale ?? 1
        )
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = true
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw mapped(error)
        }
        guard let png = pngData(for: image) else {
            throw ComputerUseError.targetUnavailable("The screenshot could not be encoded.")
        }
        return ScreenCapture(
            pngData: png,
            pixelWidth: image.width,
            pixelHeight: image.height,
            displayID: display.displayID,
            displayFrame: frame
        )
    }

    private static func pngData(for image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func mapped(_ error: any Error) -> ComputerUseError {
        if let streamError = error as? SCStreamError, streamError.code == .userDeclined {
            return .screenRecordingPermissionMissing
        }
        return .targetUnavailable("The screen could not be captured.")
    }
}
