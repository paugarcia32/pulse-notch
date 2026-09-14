import PulseNotchCore
import Testing
@testable import PulseNotchApp

@MainActor
struct TransientNotchActivityModelTests {
    @Test
    func latestActivityReplacesTheVisibleActivity() {
        let model = TransientNotchActivityModel()

        model.show(.volume(level: 24, isMuted: false))
        model.show(.brightness(level: 72))

        #expect(model.activity == .brightness(level: 72))
    }

    @Test
    func dismissRemovesTheVisibleActivity() {
        let model = TransientNotchActivityModel()
        model.show(.audioOutputConnected(name: "AirPods"))

        model.dismiss()

        #expect(model.activity == nil)
    }
}
