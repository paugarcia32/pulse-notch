import AppKit
import CoreGraphics
import PulseNotchCore

extension ScreenRect {
    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// Converts between AppKit screen coordinates (bottom-left origin) and the global
/// top-left coordinates used by Accessibility, Quartz events, and Core models.
struct CoordinateConversion: Equatable, Sendable {
    /// The height of the screen that holds the menu bar, whose AppKit origin is (0, 0).
    let primaryScreenHeight: Double

    func globalTopLeft(fromAppKit rect: CGRect) -> ScreenRect {
        ScreenRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    func appKit(fromGlobalTopLeft rect: ScreenRect) -> CGRect {
        CGRect(x: rect.x, y: primaryScreenHeight - rect.y - rect.height, width: rect.width, height: rect.height)
    }

    func globalTopLeft(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    func appKit(fromGlobalTopLeft point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }
}

struct DisplaySnapshot: Equatable, Sendable {
    let id: UInt32
    /// Global top-left coordinates.
    let frame: ScreenRect
    let backingScale: Double
}

struct DisplayLayout: Equatable, Sendable {
    /// The first display is the one holding the menu bar.
    let displays: [DisplaySnapshot]

    var primary: DisplaySnapshot? { displays.first }

    func display(containingX x: Double, y: Double) -> DisplaySnapshot? {
        displays.first { $0.frame.contains(x: x, y: y) }
    }

    func display(withID id: UInt32) -> DisplaySnapshot? {
        displays.first { $0.id == id }
    }

    @MainActor
    static func current() -> DisplayLayout {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return DisplayLayout(displays: []) }
        let conversion = CoordinateConversion(primaryScreenHeight: primary.frame.maxY)
        return DisplayLayout(displays: screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return DisplaySnapshot(
                id: number.uint32Value,
                frame: conversion.globalTopLeft(fromAppKit: screen.frame),
                backingScale: screen.backingScaleFactor
            )
        })
    }
}

enum ScreenshotScaling {
    static let maximumLongEdge = 1600

    struct PixelSize: Equatable, Sendable {
        let width: Int
        let height: Int
    }

    /// Native pixel size, reduced proportionally so the long edge stays within the
    /// cap to bound upload size and model image cost.
    static func pixelSize(
        pointWidth: Double,
        pointHeight: Double,
        backingScale: Double,
        maximumLongEdge: Int = maximumLongEdge
    ) -> PixelSize {
        let scale = max(backingScale, 1)
        let width = max(pointWidth * scale, 1)
        let height = max(pointHeight * scale, 1)
        let factor = min(1, Double(maximumLongEdge) / max(width, height))
        return PixelSize(
            width: max(1, Int((width * factor).rounded())),
            height: max(1, Int((height * factor).rounded()))
        )
    }
}
