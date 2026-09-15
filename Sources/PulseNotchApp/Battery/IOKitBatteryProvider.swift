import IOKit.ps
import PulseNotchCore

struct IOKitBatteryProvider: BatteryStatusProviding {
    func currentBatteryStatus() async throws -> BatteryStatus {
        guard let sourceInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(sourceInfo)?.takeRetainedValue() as? [CFTypeRef]
        else {
            throw BatteryStatusProviderError.unavailable
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(sourceInfo, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let level = description[kIOPSCurrentCapacityKey] as? Int
            else {
                continue
            }

            return BatteryStatus(
                chargeLevel: level,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isConnectedToPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            )
        }

        throw BatteryStatusProviderError.unavailable
    }
}
