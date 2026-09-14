import Foundation
import IOKit.graphics

enum DisplayBrightnessReader {
    static func mainDisplayBrightness() -> Float? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOMobileFramebufferShim"),
            &iterator
        ) == KERN_SUCCESS else {
            return legacyDisplayBrightness()
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(service) }

            var properties: Unmanaged<CFMutableDictionary>?
            guard
                IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                let dictionary = properties?.takeRetainedValue() as? [String: Any],
                dictionary["external"] as? Bool != true,
                let level = dictionary["IOMFBBrightnessLevel"] as? NSNumber,
                let maximum = dictionary["limit_max_physical_brightness"] as? NSNumber,
                let brightness = normalized(level: level.doubleValue, maximum: maximum.doubleValue)
            else { continue }
            return brightness
        }
        return legacyDisplayBrightness()
    }

    static func normalized(level: Double, maximum: Double) -> Float? {
        guard maximum > 0 else { return nil }
        return Float(min(max(level / maximum, 0), 1))
    }

    private static func legacyDisplayBrightness() -> Float? {
        var value: Float = 0
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleBacklightDisplay")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        guard IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &value) == kIOReturnSuccess else {
            return nil
        }
        return value
    }
}
