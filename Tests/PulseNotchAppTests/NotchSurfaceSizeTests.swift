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
    func aiAgentPageUsesALargerSurfaceOnlyForThatPage() {
        let size = NotchSurfaceSize(notchWidth: 210, notchHeight: 38, displaySize: CGSize(width: 1512, height: 982))

        #expect(size.expanded(for: .aiAgent) == CGSize(width: 640, height: 520))
        #expect(size.expanded(for: .summary) == CGSize(width: 500, height: 250))
        #expect(NotchPage.allCases.filter { size.expanded(for: $0) != size.expanded }.map(\.self) == [.aiAgent])
    }

    @Test
    func aiAgentSurfaceIsClampedToSmallDisplaysButNeverSmallerThanOtherPages() {
        let small = NotchSurfaceSize(notchWidth: nil, notchHeight: nil, displaySize: CGSize(width: 600, height: 500))
        let tiny = NotchSurfaceSize(notchWidth: nil, notchHeight: nil, displaySize: CGSize(width: 300, height: 200))

        #expect(small.aiAgentExpanded == CGSize(width: 568, height: 460))
        #expect(tiny.aiAgentExpanded == tiny.expanded)
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
