import AppKit

@MainActor
final class BrightnessChangeMonitor {
    private let onChange: @MainActor () -> Void
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            if BrightnessKeyPress.isBrightnessKeyDown(subtype: event.subtype.rawValue, data1: event.data1) {
                self?.onChange()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard BrightnessKeyPress.isBrightnessKeyDown(subtype: event.subtype.rawValue, data1: event.data1) else { return }
            Task { @MainActor in self?.onChange() }
        }
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }
}

enum BrightnessKeyPress {
    static func isBrightnessKeyDown(subtype: Int16, data1: Int) -> Bool {
        // System-defined auxiliary key events encode the media key in the high
        // word and the key-down state in the high byte of the low word.
        guard subtype == 8, (data1 >> 8) & 0xFF == 0x0A else { return false }
        let key = (data1 >> 16) & 0xFFFF
        return key == 2 || key == 3
    }
}
