import Foundation
import PulseNotchCore

@MainActor
final class BluetoothHeadphonesFeatureModel {
    private static let batteryWait: TimeInterval = 0.75

    private let provider: any BluetoothHeadphonesProviding
    private var connectedIDs: Set<String> = []
    private var pendingConnections: [String: (status: BluetoothHeadphonesStatus, deadline: Date)] = [:]
    private var hasEstablishedBaseline = false

    init(provider: any BluetoothHeadphonesProviding) {
        self.provider = provider
    }

    var hasPendingBattery: Bool { !pendingConnections.isEmpty }

    func refresh(at date: Date = .now) async -> BluetoothHeadphonesStatus? {
        guard let headphones = try? await provider.connectedHeadphones() else { return nil }
        let currentIDs = Set(headphones.map(\.id))
        let newConnection = headphones.first { !connectedIDs.contains($0.id) }
        connectedIDs = currentIDs
        pendingConnections = pendingConnections.filter { currentIDs.contains($0.key) }

        guard hasEstablishedBaseline else {
            hasEstablishedBaseline = true
            return nil
        }
        if let newConnection {
            guard newConnection.batteryLevel == nil else { return newConnection }
            pendingConnections[newConnection.id] = (newConnection, date.addingTimeInterval(Self.batteryWait))
        }

        for (id, pending) in pendingConnections {
            guard let updated = headphones.first(where: { $0.id == id }) else { continue }
            guard updated.batteryLevel != nil || date >= pending.deadline else { continue }
            pendingConnections.removeValue(forKey: id)
            return updated
        }
        return nil
    }
}
