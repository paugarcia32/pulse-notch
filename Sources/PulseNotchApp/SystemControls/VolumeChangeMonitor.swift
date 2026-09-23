import CoreAudio

@MainActor
final class VolumeChangeMonitor {
    private let onChange: @MainActor () -> Void
    private var outputDevice = AudioDeviceID()
    private var isMonitoring = false

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        addDefaultDeviceListener()
        replaceOutputDeviceListener()
    }

    func stop() {
        guard isMonitoring else { return }
        removeDefaultDeviceListener()
        removeOutputDeviceListener()
        isMonitoring = false
    }

    private func addDefaultDeviceListener() {
        var address = defaultOutputDeviceAddress
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            volumePropertyListener,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func removeDefaultDeviceListener() {
        var address = defaultOutputDeviceAddress
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            volumePropertyListener,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func replaceOutputDeviceListener() {
        removeOutputDeviceListener()
        outputDevice = currentOutputDevice()
        guard outputDevice != AudioDeviceID() else { return }

        for address in outputDeviceAddresses {
            var mutableAddress = address
            AudioObjectAddPropertyListener(
                outputDevice,
                &mutableAddress,
                volumePropertyListener,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
    }

    private func removeOutputDeviceListener() {
        guard outputDevice != AudioDeviceID() else { return }
        for address in outputDeviceAddresses {
            var mutableAddress = address
            AudioObjectRemovePropertyListener(
                outputDevice,
                &mutableAddress,
                volumePropertyListener,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
        outputDevice = AudioDeviceID()
    }

    private func currentOutputDevice() -> AudioDeviceID {
        var device = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = defaultOutputDeviceAddress
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        ) == noErr else { return AudioDeviceID() }
        return device
    }

    func handlePropertyChange() {
        guard isMonitoring else { return }
        let currentDevice = currentOutputDevice()
        if currentDevice != outputDevice { replaceOutputDeviceListener() }
        onChange()
    }

    private var defaultOutputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private var outputDeviceAddresses: [AudioObjectPropertyAddress] {
        VolumeChannelReading.channels.flatMap { channel in
            [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute].map { selector in
                AudioObjectPropertyAddress(
                    mSelector: selector,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: channel
                )
            }
        }
    }
}

private func volumePropertyListener(
    inObjectID _: AudioObjectID,
    inNumberAddresses _: UInt32,
    inAddresses _: UnsafePointer<AudioObjectPropertyAddress>,
    inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let inClientData else { return noErr }
    let monitor = Unmanaged<VolumeChangeMonitor>.fromOpaque(inClientData).takeUnretainedValue()
    Task { @MainActor in monitor.handlePropertyChange() }
    return noErr
}
