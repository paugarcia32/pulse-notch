import CoreAudio
import Foundation
import PulseNotchCore

struct SystemVolumeProvider: SystemVolumeProviding {
    func currentVolumeStatus() async throws -> SystemVolumeStatus {
        var deviceID = AudioDeviceID()
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultOutput = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutput,
            0,
            nil,
            &deviceSize,
            &deviceID
        ) == noErr else {
            throw CocoaError(.fileReadUnknown)
        }

        let volume = VolumeChannelReading.volume { channel in
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )
            guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else { return nil }
            return value
        }
        guard let volume else {
            throw CocoaError(.fileReadUnknown)
        }

        let isMuted = VolumeChannelReading.channels.contains { channel in
            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )
            return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted) == noErr && muted != 0
        }
        return SystemVolumeStatus(level: Int((volume * 100).rounded()), isMuted: isMuted)
    }
}

enum VolumeChannelReading {
    static let channels: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]

    static func volume(read: (AudioObjectPropertyElement) -> Float32?) -> Float32? {
        if let main = read(kAudioObjectPropertyElementMain) { return main }
        let values = [read(1), read(2)].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float32(values.count)
    }
}
