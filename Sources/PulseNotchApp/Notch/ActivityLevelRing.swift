import SwiftUI

struct ActivityLevelRing: View {
    let level: Int
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: 2)
            Circle()
                .trim(from: 0, to: Double(level) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 20, height: 20)
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: level)
        .accessibilityHidden(true)
    }
}
