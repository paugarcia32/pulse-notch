import Combine
import Foundation
import PulseNotchCore

@MainActor
final class MediaPlaybackFeatureModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(MediaPlaybackStatus)
        case noPlayback
        case unavailable
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var isSendingCommand = false

    private let provider: any MediaPlaybackProviding
    private var playbackClock: (id: String, elapsedTime: TimeInterval, referenceDate: Date)?
    private var pausedAt: Date?

    init(provider: any MediaPlaybackProviding) {
        self.provider = provider
    }

    var playback: MediaPlaybackStatus? {
        guard case let .loaded(playback) = state else { return nil }
        return playback
    }

    func isPageActive(at date: Date, pausedRetention: TimeInterval = 5 * 60) -> Bool {
        guard let playback else { return false }
        if playback.isPlaying { return true }
        guard let pausedAt else { return false }
        return date.timeIntervalSince(pausedAt) <= pausedRetention
    }

    func refresh(at date: Date = .now) async {
        do {
            guard let playback = try await provider.currentPlayback() else {
                playbackClock = nil
                pausedAt = nil
                state = .noPlayback
                return
            }

            updatePlaybackClock(for: playback, at: date)
            updatePauseDate(for: playback, at: date)
            state = .loaded(playback)
        } catch {
            playbackClock = nil
            pausedAt = nil
            state = .unavailable
        }
    }

    func elapsedTime(at date: Date) -> TimeInterval {
        guard
            let playback,
            playback.isPlaying,
            let playbackClock,
            playbackClock.id == playback.id
        else { return playback?.elapsedTime ?? 0 }

        return min(
            playback.duration,
            max(playback.elapsedTime, playbackClock.elapsedTime + date.timeIntervalSince(playbackClock.referenceDate))
        )
    }

    func send(_ command: MediaPlaybackCommand) async {
        guard let playback, !isSendingCommand else { return }
        isSendingCommand = true
        defer { isSendingCommand = false }

        do {
            try await provider.send(command)
        } catch {
            return
        }

        if command == .togglePlayPause {
            let updatedPlayback = MediaPlaybackStatus(
                id: playback.id,
                title: playback.title,
                artist: playback.artist,
                duration: playback.duration,
                elapsedTime: elapsedTime(at: .now),
                isPlaying: !playback.isPlaying,
                artworkData: playback.artworkData
            )
            updatePauseDate(for: updatedPlayback, at: .now)
            state = .loaded(updatedPlayback)
        }
        try? await Task.sleep(for: .milliseconds(250))
        await refresh()
    }

    private func updatePlaybackClock(for playback: MediaPlaybackStatus, at date: Date) {
        guard playback.isPlaying else {
            playbackClock = (playback.id, playback.elapsedTime, date)
            return
        }

        guard let current = playbackClock, current.id == playback.id else {
            playbackClock = (playback.id, playback.elapsedTime, date)
            return
        }

        let predictedElapsedTime = current.elapsedTime + date.timeIntervalSince(current.referenceDate)
        if playback.elapsedTime >= predictedElapsedTime - 0.25 {
            playbackClock = (playback.id, playback.elapsedTime, date)
        }
    }

    private func updatePauseDate(for playback: MediaPlaybackStatus, at date: Date) {
        if playback.isPlaying {
            pausedAt = nil
        } else if self.playback?.isPlaying != false {
            pausedAt = date
        }
    }
}
