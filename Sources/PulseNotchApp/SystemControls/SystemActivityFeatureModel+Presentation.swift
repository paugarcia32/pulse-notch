import SwiftUI

extension SystemActivityFeatureModel.Kind {
    func matches(_ other: Self) -> Bool {
        switch (self, other) {
        case (.charging, .charging), (.brightness, .brightness), (.volume, .volume), (.bluetoothHeadphones, .bluetoothHeadphones): true
        default: false
        }
    }
}

extension SystemActivityFeatureModel.Activity {
    var showsCircularLevel: Bool {
        switch kind {
        case .volume, .brightness: true
        case .charging, .bluetoothHeadphones: false
        }
    }

    var symbolName: String {
        switch kind {
        case .charging: "battery.100percent.bolt"
        case let .volume(isMuted): isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .bluetoothHeadphones: "headphones"
        }
    }

    var color: Color {
        switch kind {
        case .charging: .green
        case .volume: .white
        case .brightness: .yellow
        case .bluetoothHeadphones: .white
        }
    }

    var trailingSymbolName: String? {
        guard case let .bluetoothHeadphones(batteryLevel) = kind else { return nil }
        guard let batteryLevel else { return "battery" }

        switch batteryLevel {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var trailingColor: Color {
        if case .bluetoothHeadphones = kind { return .green }
        return color
    }

    var accessibilityLabel: String {
        return switch kind {
        case .charging: "Battery connected, \(level) percent"
        case let .volume(isMuted): isMuted ? "Volume muted" : "Volume, \(level) percent"
        case .brightness: "Display brightness, \(level) percent"
        case let .bluetoothHeadphones(batteryLevel):
            if let batteryLevel {
                "Bluetooth headphones connected, \(batteryLevel) percent battery"
            } else {
                "Bluetooth headphones connected"
            }
        }
    }
}
