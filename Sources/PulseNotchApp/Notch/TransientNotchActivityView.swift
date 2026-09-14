import PulseNotchCore
import SwiftUI

struct TransientNotchActivityView: View {
    let activity: TransientNotchActivity

    var body: some View {
        if case let .audioOutputConnected(_, batteryLevel) = activity {
            HStack(spacing: 88) {
                Image(systemName: "headphones")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 22)
                if let batteryLevel {
                    HeadphoneBatteryIndicator(level: batteryLevel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        } else {
            HStack(spacing: 14) {
                Image(systemName: symbolName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 20)
                if let level {
                    ProgressView(value: level, total: 100)
                        .tint(.mint)
                        .frame(width: 96)
                        .accessibilityLabel("\(Int(level)) percent")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var symbolName: String {
        switch activity {
        case .audioOutputConnected: "headphones"
        case let .volume(_, isMuted): isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        }
    }

    private var level: Double? {
        switch activity {
        case .audioOutputConnected: nil
        case let .volume(level, _), let .brightness(level): Double(level)
        }
    }

    private var accessibilityLabel: String {
        switch activity {
        case let .audioOutputConnected(name, batteryLevel):
            "Connected audio output: \(name)" + (batteryLevel.map { ", battery \($0) percent" } ?? "")
        case let .volume(level, isMuted): isMuted ? "Sound muted" : "Sound volume \(level) percent"
        case let .brightness(level): "Display brightness \(level) percent"
        }
    }
}

private struct HeadphoneBatteryIndicator: View {
    let level: Int

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(level) / 100)
                .stroke(level > 20 ? .mint : .orange, style: .init(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(level)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
        }
        .frame(width: 26, height: 26)
        .accessibilityLabel("Headphone battery \(level) percent")
    }
}
