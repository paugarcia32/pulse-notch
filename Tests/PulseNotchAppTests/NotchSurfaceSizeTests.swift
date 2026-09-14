import Foundation
import Testing
@testable import PulseNotchApp

struct NotchSurfaceSizeTests {
    @Test
    func usesThePhysicalNotchDimensionsWhenAvailable() {
        let size = NotchSurfaceSize(notchWidth: 210, notchHeight: 38, externalStyle: .capsule)

        #expect(size.collapsed == CGSize(width: 204, height: 38))
        #expect(size.expanded == CGSize(width: 500, height: 250))
    }

    @Test
    func usesACompactFallbackOnDisplaysWithoutANotch() {
        let size = NotchSurfaceSize(notchWidth: nil, notchHeight: nil, externalTopBarHeight: 23, externalStyle: .capsule)

        #expect(size.collapsed == CGSize(width: 140, height: 23))
    }

    @Test
    func usesTheSelectedExternalDisplayStyle() {
        #expect(NotchSurfaceSize(notchWidth: nil, notchHeight: nil, externalTopBarHeight: 23, externalStyle: .rectangle).collapsed == CGSize(width: 190, height: 23))
    }
}
