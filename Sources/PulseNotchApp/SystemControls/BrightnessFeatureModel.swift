import Combine
import PulseNotchCore

@MainActor
final class BrightnessFeatureModel: ObservableObject {
    @Published private(set) var activity: DisplayBrightnessStatus?

    private let provider: any DisplayBrightnessProviding
    private var previousStatus: DisplayBrightnessStatus?
    private var changeMonitor: BrightnessChangeMonitor?

    init(provider: any DisplayBrightnessProviding) {
        self.provider = provider
        changeMonitor = BrightnessChangeMonitor { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    func startMonitoring() async {
        changeMonitor?.start()
        await refresh()
    }

    func stopMonitoring() { changeMonitor?.stop() }

    func refresh() async {
        guard let status = try? await provider.currentDisplayBrightness() else { return }
        if let previousStatus, previousStatus != status { activity = status }
        previousStatus = status
    }

    func consumeActivity() { activity = nil }
}
