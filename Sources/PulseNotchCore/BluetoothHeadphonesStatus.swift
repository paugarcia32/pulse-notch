import Foundation

public struct BluetoothHeadphonesStatus: Identifiable, Equatable, Sendable {
    public let id: String
    public let batteryLevel: Int?

    public init(id: String, batteryLevel: Int? = nil) {
        self.id = id
        self.batteryLevel = batteryLevel.map { min(max($0, 0), 100) }
    }
}

public protocol BluetoothHeadphonesProviding: Sendable {
    func connectedHeadphones() async throws -> [BluetoothHeadphonesStatus]
}
