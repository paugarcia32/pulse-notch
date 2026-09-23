import Testing
@testable import PulseNotchApp

@MainActor
struct MediaEqualizerTests {
    @Test
    func playingEqualizerHasFiveDistinctThinBarHeightsWithinItsFrame() {
        let bars = MediaEqualizer.heights(at: 0.4, isPlaying: true, reduceMotion: false)

        #expect(bars.count == 5)
        #expect(Set(bars).count > 1)
        #expect(bars.allSatisfy { (4...15).contains($0) })
        #expect(bars != MediaEqualizer.heights(at: 0.9, isPlaying: true, reduceMotion: false))
    }

    @Test
    func pausedAndReduceMotionEqualizersStayStill() {
        let still = MediaEqualizer.heights(at: 0, isPlaying: false, reduceMotion: false)

        #expect(still.count == 5)
        #expect(MediaEqualizer.heights(at: 10, isPlaying: false, reduceMotion: false) == still)
        #expect(MediaEqualizer.heights(at: 10, isPlaying: true, reduceMotion: true) == still)
    }
}
