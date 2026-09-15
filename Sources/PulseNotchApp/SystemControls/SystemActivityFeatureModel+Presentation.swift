import SwiftUI

extension SystemActivityFeatureModel.Kind {
    func matches(_ other: Self) -> Bool {
        switch (self, other) {
        case (.charging, .charging), (.brightness, .brightness), (.volume, .volume): true
        default: false
        }
    }
}

extension SystemActivityFeatureModel.Activity {
    var showsCircularLevel: Bool {
        switch kind {
        case .volume, .brightness: true
        case .charging: false
        }
    }

    var symbolName: String {
        switch kind {
        case .charging: "battery.100percent.bolt"
        case let .volume(isMuted): isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        }
    }

    var color: Color {
        switch kind {
        case .charging: .green
        case .volume: .white
        case .brightness: .yellow
        }
    }

    var accessibilityLabel: String {
        switch kind {
        case .charging: "Battery connected, \(level) percent"
        case let .volume(isMuted): isMuted ? "Volume muted" : "Volume, \(level) percent"
        case .brightness: "Display brightness, \(level) percent"
        }
    }
}
