import Foundation

public enum TransientNotchActivity: Equatable, Sendable {
    case audioOutputConnected(name: String, batteryLevel: Int? = nil)
    case volume(level: Int, isMuted: Bool)
    case brightness(level: Int)
}
