import Foundation
import PulseNotchCore

/// Reads the system-wide media session through the bundled MediaRemote adapter.
/// The adapter exposes the artwork that MediaRemote omits from its JXA bridge.
final class MediaRemoteAdapterPlaybackProvider: @unchecked Sendable, MediaPlaybackProviding {
    private let scriptURL: URL
    private let frameworkURL: URL

    init?() {
        guard
            let scriptURL = Bundle.main.url(
                forResource: "mediaremote-adapter",
                withExtension: "pl",
                subdirectory: "MediaRemoteAdapter"
            ),
            let frameworkURL = Bundle.main.url(
                forResource: "MediaRemoteAdapter",
                withExtension: "framework",
                subdirectory: "MediaRemoteAdapter"
            )
        else { return nil }

        self.scriptURL = scriptURL
        self.frameworkURL = frameworkURL
    }

    func currentPlayback() async throws -> MediaPlaybackStatus? {
        let output = try CommandOutput.read(
            executable: "/usr/bin/perl",
            arguments: [scriptURL.path, frameworkURL.path, "get", "--now"],
            timeout: 2
        )
        return try Self.playback(from: output)
    }

    func send(_ command: MediaPlaybackCommand) async throws {
        let value = switch command {
        case .previous: 5
        case .togglePlayPause: 2
        case .next: 4
        }
        _ = try CommandOutput.read(
            executable: "/usr/bin/perl",
            arguments: [scriptURL.path, frameworkURL.path, "send", "\(value)"],
            timeout: 2
        )
    }

    static func playback(from output: String) throws -> MediaPlaybackStatus? {
        guard let info = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any] else {
            return nil
        }

        let title = string(in: info, key: "title")
        guard !title.isEmpty else { return nil }

        return MediaPlaybackStatus(
            id: string(in: info, key: "uniqueIdentifier", fallback: title),
            title: title,
            artist: string(in: info, key: "artist"),
            duration: number(in: info, key: "duration"),
            elapsedTime: number(in: info, key: "elapsedTime"),
            isPlaying: bool(in: info, key: "playing"),
            artworkData: Data(base64Encoded: string(in: info, key: "artworkData"))
        )
    }

    private static func string(in info: [String: Any], key: String, fallback: String = "") -> String {
        (info[key] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    }

    private static func number(in info: [String: Any], key: String) -> TimeInterval {
        (info[key] as? NSNumber)?.doubleValue ?? 0
    }

    private static func bool(in info: [String: Any], key: String) -> Bool {
        (info[key] as? NSNumber)?.boolValue ?? false
    }
}
