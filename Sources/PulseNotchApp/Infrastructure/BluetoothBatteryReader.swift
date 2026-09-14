import Foundation

actor BluetoothBatteryReader {
    func batteryLevel(for deviceName: String) -> Int? {
        do {
            let output = try CommandOutput.read(
                executable: "/usr/sbin/system_profiler",
                arguments: ["SPBluetoothDataType", "-xml"]
            )
            return Self.batteryLevel(in: Data(output.utf8), named: deviceName)
        } catch {
            return nil
        }
    }

    nonisolated static func batteryLevel(in data: Data, named deviceName: String) -> Int? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return nil }
        return batteryLevel(in: plist, named: deviceName, inferredName: nil)
    }

    private nonisolated static func batteryLevel(in value: Any, named deviceName: String, inferredName: String?) -> Int? {
        if let dictionary = value as? [String: Any] {
            let name = (dictionary["device_name"] as? String) ?? (dictionary["_name"] as? String) ?? inferredName
            if name?.localizedCaseInsensitiveCompare(deviceName) == .orderedSame,
               let level = batteryLevel(in: dictionary) {
                return level
            }
            for (key, child) in dictionary {
                if let level = batteryLevel(in: child, named: deviceName, inferredName: key) { return level }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let level = batteryLevel(in: child, named: deviceName, inferredName: inferredName) { return level }
            }
        }
        return nil
    }

    private nonisolated static func batteryLevel(in dictionary: [String: Any]) -> Int? {
        let left = percent(dictionary["device_batteryLevelLeft"] ?? dictionary["device_batteryPercentLeft"])
        let right = percent(dictionary["device_batteryLevelRight"] ?? dictionary["device_batteryPercentRight"])
        let earbuds = [left, right].compactMap { $0 }
        if !earbuds.isEmpty { return earbuds.min() }
        return percent(
            dictionary["device_batteryLevel"]
                ?? dictionary["device_batteryPercent"]
                ?? dictionary["device_batteryLevelSingle"]
        )
    }

    private nonisolated static func percent(_ value: Any?) -> Int? {
        let number: Int?
        switch value {
        case let value as Int: number = value
        case let value as NSNumber: number = value.intValue
        case let value as String: number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines).replacing("%", with: ""))
        default: number = nil
        }
        return number.map { min(max($0, 0), 100) }
    }
}
