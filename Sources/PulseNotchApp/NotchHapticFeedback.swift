@preconcurrency import AppKit

@MainActor
enum NotchHapticFeedback {
    static func performOpen() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }
}
