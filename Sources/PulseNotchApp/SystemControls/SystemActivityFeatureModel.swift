import Combine
import Foundation

@MainActor
final class SystemActivityFeatureModel: ObservableObject {
    enum Kind: Equatable {
        case charging
        case volume(isMuted: Bool)
        case brightness
        case bluetoothHeadphones(batteryLevel: Int?)
    }

    struct Activity: Identifiable, Equatable {
        let id = UUID()
        let kind: Kind
        let level: Int
    }

    @Published private(set) var activity: Activity?

    func present(kind: Kind, level: Int) {
        activity = Activity(kind: kind, level: level)
    }

    func dismiss(id: Activity.ID) {
        guard activity?.id == id else { return }
        activity = nil
    }
}
