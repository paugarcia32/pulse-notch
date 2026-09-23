import AppKit
import PulseNotchCore
import SwiftUI

struct MediaPlaybackPage: View {
    @ObservedObject var model: MediaPlaybackFeatureModel
    let testingPlayback: MediaPlaybackStatus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: MediaPlaybackFeatureModel, testingPlayback: MediaPlaybackStatus? = nil) {
        self.model = model
        self.testingPlayback = testingPlayback
    }

    var body: some View {
        Group {
            switch testingPlayback.map(MediaPlaybackFeatureModel.State.loaded) ?? model.state {
            case .loading:
                placeholder("Looking for media…", symbol: "waveform")
            case let .loaded(playback):
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    player(playback, elapsedTime: testingPlayback?.elapsedTime ?? model.elapsedTime(at: context.date))
                }
            case .noPlayback:
                placeholder("Nothing playing", symbol: "play.circle")
            case .unavailable:
                placeholder("Media playback is unavailable", symbol: "play.slash")
            }
        }
    }

    private func player(_ playback: MediaPlaybackStatus, elapsedTime: TimeInterval) -> some View {
        VStack(spacing: 13) {
            HStack(spacing: 12) {
                MediaArtworkView(data: playback.artworkData, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(playback.isPlaying ? "NOW PLAYING" : "PAUSED")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(playback.isPlaying ? .purple : .secondary)
                        Spacer(minLength: 8)
                        MediaEqualizer(isPlaying: playback.isPlaying, reduceMotion: reduceMotion)
                            .foregroundStyle(playback.isPlaying ? .purple : .secondary)
                    }
                    Spacer(minLength: 0)
                    Text(playback.title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(playback.artist.isEmpty ? "Unknown artist" : playback.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: 64)
            }

            VStack(spacing: 5) {
                ProgressView(value: elapsedTime, total: max(playback.duration, 1))
                    .tint(.purple)
                    .accessibilityLabel("Playback progress")
                    .accessibilityValue("\(timeTitle(elapsedTime)) of \(timeTitle(playback.duration))")
                HStack {
                    Text(timeTitle(elapsedTime))
                    Spacer(minLength: 0)
                    Text(timeTitle(playback.duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 28) {
                commandButton(.previous, symbol: "backward.fill", label: "Previous track")
                commandButton(.togglePlayPause, symbol: playback.isPlaying ? "pause.fill" : "play.fill", label: playback.isPlaying ? "Pause" : "Play")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(.white, in: Circle())
                commandButton(.next, symbol: "forward.fill", label: "Next track")
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(playback.isPlaying ? "Now playing" : "Paused"), \(playback.title), \(playback.artist.isEmpty ? "Unknown artist" : playback.artist)")
    }

    private func commandButton(_ command: MediaPlaybackCommand, symbol: String, label: String) -> some View {
        Button {
            Task { await model.send(command) }
        } label: {
            Image(systemName: symbol)
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .disabled(model.isSendingCommand)
        .accessibilityLabel(label)
    }

    private func placeholder(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func timeTitle(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded(.down))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct MediaArtworkView: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.purple.gradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct MediaEqualizer: View {
    let isPlaying: Bool
    let reduceMotion: Bool

    private static let stillHeights: [CGFloat] = [5, 9, 6, 11, 7]

    var body: some View {
        if isPlaying, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 24)) { context in
                bars(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            bars(at: 0)
        }
    }

    private func bars(at time: TimeInterval) -> some View {
        let heights = Self.heights(at: time, isPlaying: isPlaying, reduceMotion: reduceMotion)
        return HStack(spacing: 1.8) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .frame(width: 1.6, height: heights[index])
                    .frame(height: 16, alignment: .center)
            }
        }
        .frame(width: 18, height: 16)
        .accessibilityHidden(true)
    }

    static func heights(at time: TimeInterval, isPlaying: Bool, reduceMotion: Bool) -> [CGFloat] {
        guard isPlaying, !reduceMotion else { return stillHeights }
        return stillHeights.indices.map { index in
            4 + abs(sin(time * 3.4 + Double(index) * 0.9)) * 11
        }
    }
}
