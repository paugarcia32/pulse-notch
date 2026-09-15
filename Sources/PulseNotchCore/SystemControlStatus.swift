import Foundation

public struct SystemVolumeStatus: Equatable, Sendable {
    public let level: Int
    public let isMuted: Bool

    public init(level: Int, isMuted: Bool) {
        self.level = min(max(level, 0), 100)
        self.isMuted = isMuted
    }
}

public protocol SystemVolumeProviding: Sendable {
    func currentVolumeStatus() async throws -> SystemVolumeStatus
}

public struct DisplayBrightnessStatus: Equatable, Sendable {
    public let level: Int

    public init(level: Int) {
        self.level = min(max(level, 0), 100)
    }
}

public protocol DisplayBrightnessProviding: Sendable {
    func currentDisplayBrightness() async throws -> DisplayBrightnessStatus
}
