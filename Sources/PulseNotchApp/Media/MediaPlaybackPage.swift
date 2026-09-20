import AppKit
import PulseNotchCore
import SwiftUI

struct MediaPlaybackPage: View {
    @ObservedObject var model: MediaPlaybackFeatureModel
    let testingPlayback: MediaPlaybackStatus?

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
                    player(playback, elapsedTime: model.elapsedTime(at: context.date))
                }
            case .noPlayback:
                placeholder("Nothing playing", symbol: "play.circle")
            case .unavailable:
                placeholder("Media playback is unavailable", symbol: "play.slash")
            }
        }
    }

    private func player(_ playback: MediaPlaybackStatus, elapsedTime: TimeInterval) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                MediaArtworkView(data: playback.artworkData, size: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(playback.artist.isEmpty ? "Unknown artist" : playback.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                MediaEqualizer(isPlaying: playback.isPlaying, reduceMotion: false)
                    .foregroundStyle(.purple)
            }

            HStack(spacing: 8) {
                Text(timeTitle(elapsedTime))
                    .frame(width: 34, alignment: .leading)
                ProgressView(value: elapsedTime, total: max(playback.duration, 1))
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                Text(timeTitle(playback.duration))
                    .frame(width: 34, alignment: .trailing)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(spacing: 36) {
                commandButton(.previous, symbol: "backward.fill", label: "Previous track")
                commandButton(.togglePlayPause, symbol: playback.isPlaying ? "pause.fill" : "play.fill", label: playback.isPlaying ? "Pause" : "Play")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(width: 38, height: 38)
                    .background(.white, in: Circle())
                commandButton(.next, symbol: "forward.fill", label: "Next track")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing \(playback.title)")
    }

    private func commandButton(_ command: MediaPlaybackCommand, symbol: String, label: String) -> some View {
        Button {
            Task { await model.send(command) }
        } label: {
            Image(systemName: symbol)
                .frame(width: 28, height: 28)
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
                    .background(.pink.gradient)
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
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .frame(width: 3, height: height(for: index, at: time))
                    .frame(height: 16, alignment: .center)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }

    private func height(for index: Int, at time: TimeInterval) -> CGFloat {
        guard isPlaying, !reduceMotion else { return [7, 13, 9][index] }
        return 5 + abs(sin(time * 5.2 + Double(index) * 1.3)) * 11
    }
}
