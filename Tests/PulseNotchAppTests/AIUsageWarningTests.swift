import Foundation
import PulseNotchCore
import SwiftUI
import Testing
@testable import PulseNotchApp

@MainActor
struct AIUsageWarningTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func simulationDrivesIndicatorAndSummaryThroughLowExhaustedAndRecoveredStates() throws {
        let suite = "PulseNotchTests.\(#function)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchPreferences(defaults: defaults)
        preferences.setTestingFeaturesEnabled(true)
        preferences.setTestingUsageEnabled(true)
        preferences.testingUsageKind = .claude
        preferences.setUsageWarningRemainingPercent(10)

        for remaining in [10, 0, 11, 100] {
            preferences.setTestingUsageRemainingPercent(remaining)
            let data = NotchSurface.TestingPreviewData.make(preferences: preferences, at: now)
            let usage = try #require(data.usage)
            let indicators = CollapsedNotchIndicators.make(
                schedule: nil, sessions: [], actionSessions: [], usage: usage,
                usageRemainingThreshold: preferences.usageWarningRemainingPercent,
                at: now, calendarReminderLeadTime: 600
            )
            let highlight = SummaryHighlight.select(
                schedule: nil, pullRequests: [], agents: [], actions: [], media: nil,
                usage: usage, usageRemainingThreshold: preferences.usageWarningRemainingPercent,
                priorities: [.usageLimits], at: now
            )
            if remaining <= 10 {
                let indicator = try #require(indicators.first)
                #expect(indicators.count == 1)
                #expect(indicator.category == .aiUsage)
                #expect(indicator.occupiesBothSides)
                #expect(!indicator.supportsCustomColor)
                #expect(indicator.accessibilityLabel.contains("Claude Code: \(remaining) percent remaining"))
                guard case let .lowAgentUsage(warning) = indicator.content else {
                    Issue.record("Expected a low usage indicator")
                    return
                }
                #expect(highlight == .usage(kind: .claude, window: warning.window))
            } else {
                #expect(indicators.isEmpty)
                #expect(highlight == .allClear)
            }
        }
        preferences.setTestingFeaturesEnabled(false)
        #expect(!preferences.testingUsageEnabled)
        #expect(NotchSurface.TestingPreviewData.make(preferences: preferences, at: now).usage == nil)
    }

    @Test
    func quotaWarningKeepsAgentAndPercentagePairedWhenSpaceIsLimited() throws {
        let usage = CodingAgentUsage(kind: .codex, windows: [
            .init(durationMinutes: 300, usedPercent: 88, resetsAt: nil)
        ])
        let indicators = CollapsedNotchIndicators.make(
            schedule: nil, sessions: [], actionSessions: [],
            usage: [.available(usage)], at: now, calendarReminderLeadTime: 600
        )
        let warning = try #require(indicators.first)
        let layout = CollapsedNotchLayout(
            indicators: [warning, CollapsedIndicatorPreview.claude.indicator(instance: 0)],
            maximumPerSide: 1
        )

        let level = try #require(layout.levels.first)
        #expect(layout.levels.count == 1)
        #expect(level.left?.id == warning.id)
        #expect(level.right?.id == warning.id)
        #expect(level.width >= 38)
    }

    @Test(arguments: [0.0, 0.5, 12, 100])
    func remainingPercentageFitsItsCollapsedLane(remaining: Double) {
        let view = NSHostingView(rootView: AgentUsageRemainingValue(
            remainingPercent: remaining, color: .orange, reduceMotion: true
        ))
        #expect(view.fittingSize.width <= 38)
    }

    @Test
    func thresholdAndVisibilityPersistIndependentlyOfAgentActivity() throws {
        let suite = "PulseNotchTests.\(#function)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        // Existing installations gain the new category without losing their choices.
        defaults.set(["calendar"], forKey: "settings.visibleCollapsedIndicatorCategories")
        let preferences = NotchPreferences(defaults: defaults)
        #expect(preferences.usageWarningRemainingPercent == 20)
        #expect(preferences.isCollapsedIndicatorCategoryEnabled(.aiUsage))
        #expect(!preferences.isCollapsedIndicatorCategoryEnabled(.codingAgents))
        preferences.setUsageWarningRemainingPercent(5)
        preferences.setCollapsedIndicatorCategory(.aiUsage, isVisible: false)

        let restored = NotchPreferences(defaults: defaults)
        #expect(restored.usageWarningRemainingPercent == 5)
        #expect(!restored.isCollapsedIndicatorCategoryEnabled(.aiUsage))
        #expect(restored.isCollapsedIndicatorCategoryEnabled(.calendar))
        #expect(restored.collapsedIndicatorPriorityOrder.contains(.aiUsage))
        preferences.setUsageWarningRemainingPercent(-1)
        #expect(preferences.usageWarningRemainingPercent == 0)
        preferences.setUsageWarningRemainingPercent(101)
        #expect(preferences.usageWarningRemainingPercent == 100)
    }
}
