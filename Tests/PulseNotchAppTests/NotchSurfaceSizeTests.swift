import Foundation
import Testing
@testable import PulseNotchApp

struct NotchSurfaceSizeTests {
    @Test
    func usesThePhysicalNotchDimensionsWhenAvailable() {
        let size = NotchSurfaceSize(notchWidth: 210, notchHeight: 38)

        #expect(size.physicalNotchSize == CGSize(width: 210, height: 38))
        #expect(size.collapsed == CGSize(width: 426, height: 38))
        #expect(size.expanded == CGSize(width: 500, height: 250))
    }

    @Test
    func usesRectangularNotchOnDisplaysWithoutANotch() {
        let size = NotchSurfaceSize(notchWidth: nil, notchHeight: nil, externalTopBarHeight: 23)

        #expect(size.physicalNotchSize == nil)
        #expect(size.collapsed == CGSize(width: 190, height: 23))
    }

    @Test
    func externalSystemActivityPlacesItsTwoLanesAtOppositeEdges() {
        let size = NotchSurfaceSize(notchWidth: nil, notchHeight: nil, externalTopBarHeight: 23)
        let gap = SystemActivityLayout.externalCenterWidth(for: size.collapsed.width)

        #expect(gap == 114)
        #expect(SystemActivityLayout.sideWidth + gap + SystemActivityLayout.sideWidth == size.collapsed.width)
        #expect(SystemActivityLayout.sideWidth / 2 == 19)
        #expect(SystemActivityLayout.sideWidth + gap + SystemActivityLayout.sideWidth / 2 == 171)
    }
}
