import Foundation
import PulseNotchCore

/// Keeps the private system bridge at the app boundary. Apple does not expose a
/// public API for another app's Now Playing item, so metadata is read through the
/// system-owned JXA host, which has access to the current global media session.
final class MediaRemotePlaybackProvider: @unchecked Sendable, MediaPlaybackProviding {
    private typealias SendCommand = @convention(c) (Int, AnyObject?) -> Void

    private let sendCommand: SendCommand

    init?() {
        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
            ),
            let commandPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString)
        else { return nil }

        sendCommand = unsafeBitCast(commandPointer, to: SendCommand.self)
    }

    func currentPlayback() async throws -> MediaPlaybackStatus? {
        let output = try CommandOutput.read(
            executable: "/usr/bin/osascript",
            arguments: ["-l", "JavaScript"],
            standardInput: Self.nowPlayingScript,
            timeout: 2
        )
        return try Self.playback(from: output)
    }

    static func playback(from output: String) throws -> MediaPlaybackStatus? {
        guard let info = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any] else {
            return nil
        }
        let title = string(in: info, keys: ["title"])
        guard !title.isEmpty else { return nil }
        let duration = number(in: info, keys: ["duration"])
        let elapsedTime = number(in: info, keys: ["elapsedTime"])
        let rate = number(in: info, keys: ["playbackRate"])
        let artworkData = string(in: info, keys: ["artworkData"])

        return MediaPlaybackStatus(
            id: string(in: info, keys: ["uniqueIdentifier", "title"]),
            title: title,
            artist: string(in: info, keys: ["artist"]),
            duration: duration,
            elapsedTime: elapsedTime,
            isPlaying: bool(in: info, keys: ["isPlaying"]) ?? (rate > 0),
            artworkData: Data(base64Encoded: artworkData)
        )
    }

    func send(_ command: MediaPlaybackCommand) async throws {
        let value = switch command {
        case .previous: 5
        case .togglePlayPause: 2
        case .next: 4
        }
        sendCommand(value, nil)
    }

    private static func value(in info: [String: Any], keys: [String]) -> Any? {
        keys.lazy.compactMap { info[$0] }.first
    }

    private static func string(in info: [String: Any], keys: [String]) -> String {
        value(in: info, keys: keys) as? String ?? ""
    }

    private static func number(in info: [String: Any], keys: [String]) -> TimeInterval {
        (value(in: info, keys: keys) as? NSNumber)?.doubleValue ?? 0
    }

    private static func bool(in info: [String: Any], keys: [String]) -> Bool? {
        (value(in: info, keys: keys) as? NSNumber)?.boolValue
    }

    private static let nowPlayingScript = """
    ObjC.import('Foundation');

    function stringValue(dictionary, key) {
      const value = dictionary.objectForKey($(key));
      return value.isNil() ? '' : String(value.js);
    }

    function numberValue(dictionary, key) {
      const value = dictionary.objectForKey($(key));
      return value.isNil() ? 0 : Number(value.doubleValue);
    }

    function artworkValue(dictionary) {
      const value = dictionary.objectForKey($('kMRMediaRemoteNowPlayingInfoArtworkData'));
      if (value.isNil()) { return ''; }
      const encoded = value.base64EncodedStringWithOptions(0);
      return encoded.isNil() ? '' : String(encoded.js);
    }

    function run() {
      const framework = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
      framework.load;
      const request = $.NSClassFromString('MRNowPlayingRequest');
      const item = request.localNowPlayingItem;
      if (item.isNil()) { return JSON.stringify({}); }

      const info = item.nowPlayingInfo;
      const title = stringValue(info, 'kMRMediaRemoteNowPlayingInfoTitle');
      if (!title) { return JSON.stringify({}); }

      return JSON.stringify({
        uniqueIdentifier: stringValue(info, 'kMRMediaRemoteNowPlayingInfoUniqueIdentifier') || title,
        title: title,
        artist: stringValue(info, 'kMRMediaRemoteNowPlayingInfoArtist'),
        duration: numberValue(info, 'kMRMediaRemoteNowPlayingInfoDuration'),
        elapsedTime: item.metadata.calculatedPlaybackPosition,
        playbackRate: numberValue(info, 'kMRMediaRemoteNowPlayingInfoPlaybackRate'),
        isPlaying: ObjC.unwrap(request.localIsPlaying),
        artworkData: artworkValue(info)
      });
    }
    """
}
