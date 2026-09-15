import Combine
import Foundation
import PulseNotchCore

@MainActor
final class BatteryFeatureModel: ObservableObject {
    struct ChargingActivity: Identifiable, Equatable {
        let id = UUID()
        let chargeLevel: Int
    }

    enum State: Equatable {
        case loading
        case loaded(BatteryStatus)
        case unavailable
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var chargingActivity: ChargingActivity?

    private let provider: any BatteryStatusProviding
    private var previousStatus: BatteryStatus?

    init(provider: any BatteryStatusProviding) {
        self.provider = provider
    }

    func refresh() async {
        do {
            let status = try await provider.currentBatteryStatus()
            if previousStatus?.isConnectedToPower == false, status.isConnectedToPower {
                showChargingActivity(chargeLevel: status.chargeLevel)
            }
            previousStatus = status
            state = .loaded(status)
        } catch {
            state = .unavailable
        }
    }

    func dismissChargingActivity(id: ChargingActivity.ID) {
        guard chargingActivity?.id == id else { return }
        chargingActivity = nil
    }

    func showChargingActivity(chargeLevel: Int) {
        chargingActivity = ChargingActivity(chargeLevel: chargeLevel)
    }
}
