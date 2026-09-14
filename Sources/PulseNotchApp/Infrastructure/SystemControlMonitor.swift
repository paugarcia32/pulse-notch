import CoreAudio
import PulseNotchCore
import Combine

@MainActor
final class SystemControlMonitor: ObservableObject {
    @Published private(set) var activity: TransientNotchActivity?

    private var outputDevice = kAudioObjectUnknown
    private var connectedBluetoothDevices: Set<AudioObjectID> = []
    private var volume: Float?
    private var brightness: Float?
    private var brightnessTimer: Timer?
    private var batteryLookupTask: Task<Void, Never>?
    private var currentHeadphoneName: String?
    private var isStarted = false
    private let batteryReader = BluetoothBatteryReader()

    private var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private var deviceListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard !isStarted else { return }
        isStarted = true
        outputDevice = defaultOutputDevice()
        volume = outputVolume(for: outputDevice)
        connectedBluetoothDevices = bluetoothOutputDevices()
        brightness = DisplayBrightnessReader.mainDisplayBrightness()
        listenForDefaultOutputChanges()
        listenForAudioDeviceChanges()
        listenForVolumeChanges(on: outputDevice)
        brightnessTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readBrightnessChange() }
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            .main,
            defaultOutputChanged
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceListAddress,
            .main,
            audioDevicesChanged
        )
        removeVolumeListener()
        brightnessTimer?.invalidate()
        brightnessTimer = nil
        batteryLookupTask?.cancel()
    }

    private func listenForDefaultOutputChanges() {
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            .main,
            defaultOutputChanged
        )
    }

    private func listenForAudioDeviceChanges() {
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceListAddress,
            .main,
            audioDevicesChanged
        )
    }

    private func listenForVolumeChanges(on device: AudioObjectID) {
        guard device != kAudioObjectUnknown else { return }
        AudioObjectAddPropertyListenerBlock(device, &volumeAddress, .main, volumeChanged)
    }

    private func removeVolumeListener() {
        guard outputDevice != kAudioObjectUnknown else { return }
        AudioObjectRemovePropertyListenerBlock(outputDevice, &volumeAddress, .main, volumeChanged)
    }

    private lazy var defaultOutputChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.defaultOutputDidChange()
    }

    private lazy var volumeChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.volumeDidChange()
    }

    private lazy var audioDevicesChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.audioDevicesDidChange()
    }

    private func defaultOutputDidChange() {
        let previousDevice = outputDevice
        let newDevice = defaultOutputDevice()
        guard newDevice != previousDevice else { return }
        removeVolumeListener()
        outputDevice = newDevice
        volume = outputVolume(for: newDevice)
        listenForVolumeChanges(on: newDevice)

        if isBluetoothDevice(newDevice), !connectedBluetoothDevices.contains(newDevice), let name = deviceName(newDevice) {
            announceHeadphones(named: name)
        }
    }

    private func audioDevicesDidChange() {
        let newDevices = bluetoothOutputDevices()
        if let device = newDevices.subtracting(connectedBluetoothDevices).first, let name = deviceName(device) {
            announceHeadphones(named: name)
        }
        connectedBluetoothDevices = newDevices
    }

    private func volumeDidChange() {
        guard let newVolume = outputVolume(for: outputDevice), newVolume != volume else { return }
        volume = newVolume
        activity = .volume(level: Int((newVolume * 100).rounded()), isMuted: newVolume == 0)
    }

    private func announceHeadphones(named name: String) {
        currentHeadphoneName = name
        activity = .audioOutputConnected(name: name)
        batteryLookupTask?.cancel()
        batteryLookupTask = Task { [weak self, batteryReader] in
            for retry in 0...1 {
                if let batteryLevel = await batteryReader.batteryLevel(for: name) {
                    guard !Task.isCancelled, self?.currentHeadphoneName == name else { return }
                    self?.activity = .audioOutputConnected(name: name, batteryLevel: batteryLevel)
                    return
                }
                if retry == 0 { try? await Task.sleep(for: .seconds(1)) }
            }
        }
    }

    private func readBrightnessChange() {
        guard let newBrightness = DisplayBrightnessReader.mainDisplayBrightness(), newBrightness != brightness else { return }
        brightness = newBrightness
        activity = .brightness(level: Int((newBrightness * 100).rounded()))
    }

    private func defaultOutputDevice() -> AudioObjectID {
        var device = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            0,
            nil,
            &size,
            &device
        )
        return status == noErr ? device : kAudioObjectUnknown
    }

    private func outputVolume(for device: AudioObjectID) -> Float? {
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &volumeAddress) else { return nil }
        var volume: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &volume)
        return status == noErr ? volume : nil
    }

    private func bluetoothOutputDevices() -> Set<AudioObjectID> {
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceListAddress,
            0,
            nil,
            &size
        ) == noErr else { return [] }
        var devices = Array(repeating: AudioObjectID(), count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceListAddress,
            0,
            nil,
            &size,
            &devices
        ) == noErr else { return [] }
        return Set(devices.filter(isBluetoothDevice))
    }

    private func isBluetoothDevice(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private func deviceName(_ device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeUnretainedValue() as String?
    }

}
