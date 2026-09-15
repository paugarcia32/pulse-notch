import Foundation
import IOBluetooth
import IOKit
import PulseNotchCore

actor BluetoothHeadphonesProvider: BluetoothHeadphonesProviding {
    private struct Headphones: Sendable {
        let id: String
        let name: String
    }

    private var cachedBatteryLevels: [String: Int] = [:]
    private var lastBatteryRead: Date?
    private var isBatteryRefreshInFlight = false

    func connectedHeadphones() async throws -> [BluetoothHeadphonesStatus] {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        let headphones = pairedDevices.compactMap { device -> Headphones? in
            guard device.isConnected(), isAudioDevice(device), let address = device.addressString else { return nil }
            return Headphones(id: address, name: device.name ?? "")
        }

        if !headphones.isEmpty, needsBatteryRefresh, !isBatteryRefreshInFlight {
            lastBatteryRead = .now
            isBatteryRefreshInFlight = true
            Task.detached { [weak self, headphones] in
                let levels = Self.readBatteryLevels(for: headphones)
                await self?.storeBatteryLevels(levels)
            }
        }

        return headphones.map { headphones in
            BluetoothHeadphonesStatus(id: headphones.id, batteryLevel: cachedBatteryLevels[headphones.id])
        }
    }

    private var needsBatteryRefresh: Bool {
        lastBatteryRead.map { Date.now.timeIntervalSince($0) >= 20 } ?? true
    }

    private func storeBatteryLevels(_ levels: [String: Int]) {
        cachedBatteryLevels = levels
        isBatteryRefreshInFlight = false
    }

    private func isAudioDevice(_ device: IOBluetoothDevice) -> Bool {
        let majorDeviceClass = (Int(device.classOfDevice) >> 8) & 0x1F
        return majorDeviceClass == 0x04
    }

    private static func readBatteryLevels(for headphones: [Headphones]) -> [String: Int] {
        var levels = registryBatteryLevels(for: headphones)
        let profilerLevels = Self.systemProfilerBatteryLevels()
        for headphones in headphones where levels[headphones.id] == nil {
            levels[headphones.id] = profilerLevels.addresses[Self.normalizedAddress(headphones.id)]
                ?? profilerLevels.names[Self.normalizedName(headphones.name)]
        }

        let unresolved = headphones.filter { levels[$0.id] == nil }
        guard !unresolved.isEmpty else { return levels }
        let accessoryLevels = Self.accessoryBatteryLevels()

        for headphones in unresolved {
            guard let level = accessoryLevels[Self.normalizedName(headphones.name)] else { continue }
            levels[headphones.id] = level
        }

        return levels
    }

    private static func registryBatteryLevels(for headphones: [Headphones]) -> [String: Int] {
        var levels: [String: Int] = [:]
        var iterator = io_iterator_t()
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return levels }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }

            guard let level = property("BatteryPercent", from: entry) as? Int else { continue }
            let address = property("DeviceAddress", from: entry) as? String
                ?? property("BD_ADDR", from: entry) as? String
            let name = property("ProductName", from: entry) as? String
                ?? property("Product", from: entry) as? String

            for headphones in headphones where addressesMatch(address, headphones.id) || normalizedName(name) == normalizedName(headphones.name) {
                levels[headphones.id] = min(max(level, 0), 100)
            }
        }

        return levels
    }

    private static func property(_ key: String, from entry: io_registry_entry_t) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func addressesMatch(_ lhs: String?, _ rhs: String) -> Bool {
        guard let lhs else { return false }
        return normalizedAddress(lhs) == normalizedAddress(rhs)
    }

    static func accessoryBatteryLevels(output: String) -> [String: Int] {
        guard let expression = try? NSRegularExpression(
            pattern: #"^\s*-\s*(.+?)\s*(?:\(.+?\))?\s+(\d+)\s*%"#,
            options: [.anchorsMatchLines]
        ) else { return [:] }

        let outputRange = NSRange(output.startIndex..., in: output)
        return expression.matches(in: output, range: outputRange).reduce(into: [:]) { levels, match in
            guard let nameRange = Range(match.range(at: 1), in: output),
                  let levelRange = Range(match.range(at: 2), in: output),
                  let level = Int(output[levelRange])
            else { return }
            levels[normalizedName(String(output[nameRange]))] = min(max(level, 0), 100)
        }
    }

    private static func accessoryBatteryLevels() -> [String: Int] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "accps"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return [:] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return [:] }
        return accessoryBatteryLevels(output: text)
    }

    private static func systemProfilerBatteryLevels() -> (addresses: [String: Int], names: [String: Int]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return ([:], [:]) }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let root = (object["SPBluetoothDataType"] as? [[String: Any]])?.first
        else { return ([:], [:]) }

        return profilerBatteryLevels(root: root)
    }

    static func profilerBatteryLevels(root: [String: Any]) -> (addresses: [String: Int], names: [String: Int]) {
        guard let connected = root["device_connected"] as? [[String: [String: Any]]] else { return ([:], [:]) }
        var addresses: [String: Int] = [:]
        var names: [String: Int] = [:]

        for devices in connected {
            for (name, payload) in devices {
                let levels = [
                    payload["device_batteryLevelLeft"],
                    payload["device_batteryLevelRight"],
                    payload["device_batteryLevelMain"],
                    payload["device_batteryLevel"],
                    payload["device_batteryLevelCase"]
                ].compactMap(batteryPercentage)
                guard let level = levels.max() else { continue }

                let normalizedName = normalizedName(name)
                if !normalizedName.isEmpty { names[normalizedName] = level }
                if let address = payload["device_address"] as? String {
                    let normalizedAddress = normalizedAddress(address)
                    if !normalizedAddress.isEmpty { addresses[normalizedAddress] = level }
                }
            }
        }

        return (addresses, names)
    }

    private static func batteryPercentage(_ value: Any?) -> Int? {
        if let value = value as? Int { return min(max(value, 0), 100) }
        guard let value = value as? String else { return nil }
        let digits = value.filter(\.isNumber)
        return Int(digits).map { min(max($0, 0), 100) }
    }

    private static func normalizedAddress(_ address: String) -> String {
        address.filter(\.isHexDigit).uppercased()
    }

    private static func normalizedName(_ name: String?) -> String {
        String((name ?? "").lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
