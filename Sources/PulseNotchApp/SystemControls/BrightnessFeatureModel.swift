import Combine
import PulseNotchCore

@MainActor
final class BrightnessFeatureModel: ObservableObject {
    @Published private(set) var activity: DisplayBrightnessStatus?

    private let provider: any DisplayBrightnessProviding
    private var changeMonitor: BrightnessChangeMonitor?

    init(provider: any DisplayBrightnessProviding) {
        self.provider = provider
        changeMonitor = BrightnessChangeMonitor { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refreshForBrightnessKeyPress()
            }
        }
    }

    func startMonitoring() {
        changeMonitor?.start()
    }

    func stopMonitoring() { changeMonitor?.stop() }

    func refreshForBrightnessKeyPress() async {
        guard let status = try? await provider.currentDisplayBrightness() else { return }
        activity = status
    }

    func consumeActivity() { activity = nil }
}
