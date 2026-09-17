import PulseNotchCore

struct UnavailableMediaPlaybackProvider: MediaPlaybackProviding {
    func currentPlayback() async throws -> MediaPlaybackStatus? {
        throw MediaPlaybackProviderError.unavailable
    }

    func send(_ command: MediaPlaybackCommand) async throws {
        throw MediaPlaybackProviderError.unavailable
    }
}
