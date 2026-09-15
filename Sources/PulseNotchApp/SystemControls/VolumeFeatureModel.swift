import Combine
import PulseNotchCore

@MainActor
final class VolumeFeatureModel: ObservableObject {
    @Published private(set) var activity: SystemVolumeStatus?

    private let provider: any SystemVolumeProviding
    private var previousStatus: SystemVolumeStatus?
    private var changeMonitor: VolumeChangeMonitor?

    init(provider: any SystemVolumeProviding) {
        self.provider = provider
        changeMonitor = VolumeChangeMonitor { [weak self] in
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
        guard let status = try? await provider.currentVolumeStatus() else { return }
        if let previousStatus, previousStatus != status { activity = status }
        previousStatus = status
    }

    func consumeActivity() { activity = nil }
}
