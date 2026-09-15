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

        var volume: Float32 = 0
        var volumeSize = UInt32(MemoryLayout<Float32>.size)
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &volumeSize, &volume) == noErr else {
            throw CocoaError(.fileReadUnknown)
        }

        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let isMuted = AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &muteSize, &muted) == noErr && muted != 0
        return SystemVolumeStatus(level: Int((volume * 100).rounded()), isMuted: isMuted)
    }
}
