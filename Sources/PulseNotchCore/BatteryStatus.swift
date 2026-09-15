import Foundation

public struct BatteryStatus: Equatable, Sendable {
    public let chargeLevel: Int
    public let isCharging: Bool
    public let isConnectedToPower: Bool

    public init(chargeLevel: Int, isCharging: Bool, isConnectedToPower: Bool) {
        self.chargeLevel = min(max(chargeLevel, 0), 100)
        self.isCharging = isCharging
        self.isConnectedToPower = isConnectedToPower
    }
}

public protocol BatteryStatusProviding: Sendable {
    func currentBatteryStatus() async throws -> BatteryStatus
}

public enum BatteryStatusProviderError: Error, Equatable, Sendable {
    case unavailable
}
