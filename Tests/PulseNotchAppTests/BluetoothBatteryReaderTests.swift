import Foundation
import Testing
@testable import PulseNotchApp

struct BluetoothBatteryReaderTests {
    @Test
    func usesTheLowestAvailableEarbudBatteryForTheConnectedDevice() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "SPBluetoothDataType": [[
                    "device_connected": [[
                        "AirPods Pau": [
                            "device_batteryLevelLeft": "92%",
                            "device_batteryLevelRight": "78%",
                            "device_batteryLevelCase": "100%"
                        ]
                    ]]
                ]]
            ],
            format: .xml,
            options: 0
        )

        #expect(BluetoothBatteryReader.batteryLevel(in: data, named: "AirPods Pau") == 78)
    }

    @Test
    func returnsNoBatteryWhenTheDeviceHasNoBatteryProperties() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "SPBluetoothDataType": [[
                    "device_connected": [[
                        "AirPods Pau": ["device_address": "AA:BB"]
                    ]]
                ]]
            ],
            format: .xml,
            options: 0
        )

        #expect(BluetoothBatteryReader.batteryLevel(in: data, named: "AirPods Pau") == nil)
    }
}
