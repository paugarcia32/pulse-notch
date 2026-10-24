import Foundation

public struct CodingAgentUsageWarning: Equatable, Sendable {
    public let kind: CodingAgentKind
    public let window: CodingAgentUsage.Window

    public static func select(
        in availability: [CodingAgentUsageAvailability],
        remainingThreshold: Int = 20,
        at date: Date
    ) -> Self? {
        let threshold = Double(min(max(remainingThreshold, 0), 100))
        return availability.compactMap { item -> CodingAgentUsage? in
            guard case let .available(usage) = item else { return nil }
            return usage
        }.flatMap { usage in
            usage.windows.compactMap { window -> Self? in
                guard window.usedPercent.isFinite,
                      (0...100).contains(window.usedPercent),
                      window.resetsAt.map({ $0 > date }) ?? true,
                      window.remainingPercent <= threshold else { return nil }
                return Self(kind: usage.kind, window: window)
            }
        }.min { $0.window.remainingPercent < $1.window.remainingPercent }
    }
}
