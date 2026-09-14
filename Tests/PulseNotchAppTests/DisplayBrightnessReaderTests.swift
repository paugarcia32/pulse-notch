import Testing
@testable import PulseNotchApp

struct DisplayBrightnessReaderTests {
    @Test
    func normalizesTheFramebufferBrightnessToAPercentage() {
        #expect(DisplayBrightnessReader.normalized(level: 52_428_800, maximum: 104_857_600) == 0.5)
    }

    @Test
    func rejectsAnInvalidBrightnessRange() {
        #expect(DisplayBrightnessReader.normalized(level: 1, maximum: 0) == nil)
    }
}
