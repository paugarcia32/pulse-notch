import AppKit
import Carbon.HIToolbox

@MainActor
final class GlobalShortcutManager {
    private static let signature: UInt32 = 0x504E4B48 // PNKH

    private let onShortcut: (ShortcutAction) -> Void
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    init(onShortcut: @escaping (ShortcutAction) -> Void) {
        self.onShortcut = onShortcut

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            globalShortcutEventHandler,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    func stop() {
        hotKeys.values.forEach { _ = UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    func replace(with shortcuts: [ShortcutAction: AppShortcut]) {
        hotKeys.values.forEach { _ = UnregisterEventHotKey($0) }
        hotKeys.removeAll(keepingCapacity: true)

        for (index, action) in ShortcutAction.allCases.enumerated() {
            guard action == .openNotch else { continue }
            guard let shortcut = shortcuts[action], let keyCode = shortcut.carbonKeyCode else { continue }
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(
                keyCode,
                shortcut.carbonModifiers,
                EventHotKeyID(signature: Self.signature, id: UInt32(index)),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if result == noErr, let ref { hotKeys[UInt32(index)] = ref }
        }
    }

    fileprivate func handle(hotKeyID: UInt32) {
        guard let action = ShortcutAction.allCases[safe: Int(hotKeyID)] else { return }
        onShortcut(action)
    }
}

private func globalShortcutEventHandler(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let result = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard result == noErr else { return result }

    let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
    let hotKeyIDValue = hotKeyID.id
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(50))
        manager.handle(hotKeyID: hotKeyIDValue)
    }
    return noErr
}

private extension AppShortcut {
    var carbonKeyCode: UInt32? {
        if let keyCode { return UInt32(keyCode) }
        switch key.lowercased() {
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        case "n": return 45
        default: return nil
        }
    }

    var carbonModifiers: UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
