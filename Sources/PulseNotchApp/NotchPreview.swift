import PulseNotchCore
import SwiftUI

struct NotchPreview: View {
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 24) {
            notch

            Text("Hover over the notch to preview its expanded state.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 560, height: 260)
        .background(.regularMaterial)
    }

    private var notch: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "waveform" : "circle.fill")
                    .foregroundStyle(.green)

                if isExpanded {
                    Text("Pulse Notch")
                        .font(.headline)

                    Spacer(minLength: 20)

                    Image(systemName: "play.fill")
                        .accessibilityLabel("Play")
                }
            }

            if isExpanded {
                Divider()

                Label("No activity yet", systemImage: "bell.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(
            width: isExpanded ? 420 : 190,
            height: isExpanded ? 112 : 42,
            alignment: .top
        )
        .background(.black, in: RoundedRectangle(cornerRadius: 18))
        .animation(.snappy(duration: 0.25), value: isExpanded)
        .onHover { isExpanded = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pulse Notch")
    }
}

