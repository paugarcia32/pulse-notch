import Foundation

public struct MediaPlaybackStatus: Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let duration: TimeInterval
    public let elapsedTime: TimeInterval
    public let isPlaying: Bool
    public let artworkData: Data?

    public init(
        id: String,
        title: String,
        artist: String,
        duration: TimeInterval,
        elapsedTime: TimeInterval,
        isPlaying: Bool,
        artworkData: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = max(duration, 0)
        self.elapsedTime = min(max(elapsedTime, 0), max(duration, 0))
        self.isPlaying = isPlaying
        self.artworkData = artworkData
    }
}

public enum MediaPlaybackCommand: Sendable {
    case previous
    case togglePlayPause
    case next
}

public protocol MediaPlaybackProviding: Sendable {
    func currentPlayback() async throws -> MediaPlaybackStatus?
    func send(_ command: MediaPlaybackCommand) async throws
}

public enum MediaPlaybackProviderError: Error, Equatable, Sendable {
    case unavailable
}
