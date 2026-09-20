import AppKit
import PulseNotchCore
import SwiftUI

extension CodingAgentKind {
    var notchColor: Color {
        switch self {
        case .codex: .cyan
        case .claude: .orange
        case .cursor: .purple
        case .antigravity: .indigo
        case .opencode: .mint
        }
    }
}

struct NotchIndicator: Identifiable {
    enum Content: Equatable {
        case upcomingCalendarEvent(minutesUntilStart: Int)
        case runningAgent(CodingAgentKind)
        case completedAgent(CodingAgentKind)
        case runningDownload(percentage: Int?)
        case githubActions(GitHubPullRequest.ActionStatus)
        case mediaPlayback(MediaPlaybackStatus)
        case clock(ClockStatus)
    }

    let id: String
    let content: Content
    let accessibilityLabel: String

    var color: Color {
        switch content {
        case .upcomingCalendarEvent: .pink
        case let .runningAgent(kind): kind.notchColor
        case .completedAgent: .green
        case .runningDownload: .blue
        case .githubActions(.running): .orange
        case .githubActions(.failed): .red
        case .githubActions: .green
        case .mediaPlayback: .purple
        case .clock: .orange
        }
    }

    var category: CollapsedNotchIndicatorCategory {
        switch content {
        case .upcomingCalendarEvent: .calendar
        case .githubActions: .githubActions
        case .runningAgent, .completedAgent: .codingAgents
        case .runningDownload: .downloads
        case .mediaPlayback: .mediaPlayback
        case .clock: .clock
        }
    }

    var occupiesBothSides: Bool {
        switch content {
        case .upcomingCalendarEvent, .runningDownload, .mediaPlayback, .clock: true
        default: false
        }
    }

    var supportsCustomColor: Bool {
        switch content {
        case .upcomingCalendarEvent, .runningAgent, .runningDownload, .githubActions(.running), .mediaPlayback, .clock:
            true
        case .completedAgent, .githubActions:
            false
        }
    }

}

enum CollapsedNotchIndicatorCategory: String, CaseIterable, Codable, Identifiable {
    case calendar
    case githubActions
    case codingAgents
    case downloads
    case mediaPlayback
    case clock

    var id: String { "collapsed-indicator-\(rawValue)" }
    var colorPickerID: String { "collapsed-indicator-color-\(rawValue)" }

    var name: String {
        switch self {
        case .calendar: "Calendar reminders"
        case .githubActions: "GitHub Actions"
        case .codingAgents: "Coding agents"
        case .downloads: "Downloads"
        case .mediaPlayback: "Media playback"
        case .clock: "Clock"
        }
    }

    var ownerPage: NotchPage? {
        switch self {
        case .calendar: .calendar
        case .githubActions: .github
        case .codingAgents: .agents
        case .downloads: .downloads
        case .mediaPlayback: .media
        case .clock: .clock
        }
    }

    var symbolName: String {
        switch self {
        case .calendar: "calendar"
        case .githubActions: "arrow.triangle.2.circlepath"
        case .codingAgents: "terminal"
        case .downloads: "arrow.down.circle"
        case .mediaPlayback: "waveform"
        case .clock: "timer"
        }
    }

    var defaultColor: Color {
        switch self {
        case .calendar: .pink
        case .githubActions: .orange
        case .codingAgents: .cyan
        case .downloads: .blue
        case .mediaPlayback: .purple
        case .clock: .orange
        }
    }

    static let defaultPriorityOrder: [Self] = [
        .mediaPlayback,
        .clock,
        .calendar,
        .githubActions,
        .downloads,
        .codingAgents
    ]

}

enum CollapsedIndicatorPreview: String, CaseIterable, Identifiable {
    case calendar
    case githubActions
    case codex
    case claude
    case cursor
    case antigravity
    case opencode
    case download
    case mediaPlayback
    case clock

    var id: String { rawValue }

    var name: String {
        switch self {
        case .calendar: "Calendar countdown"
        case .githubActions: "GitHub Actions"
        case .codex: "Codex agent"
        case .claude: "Claude agent"
        case .cursor: "Cursor agent"
        case .antigravity: "Antigravity agent"
        case .opencode: "OpenCode agent"
        case .download: "Download"
        case .mediaPlayback: "Media playback"
        case .clock: "Running timer"
        }
    }

    var maximumPreviewCount: Int {
        self == .calendar || self == .clock ? 1 : 5
    }

    func indicator(instance: Int) -> NotchIndicator {
        switch self {
        case .calendar:
            return NotchIndicator(id: "\(rawValue)-\(instance)", content: .upcomingCalendarEvent(minutesUntilStart: 31), accessibilityLabel: "Next calendar event starts in 31 minutes")
        case .githubActions:
            return NotchIndicator(id: "\(rawValue)-\(instance)", content: .githubActions(.running), accessibilityLabel: "GitHub Actions running")
        case .codex: return runningAgent(.codex, instance: instance)
        case .claude: return runningAgent(.claude, instance: instance)
        case .cursor: return runningAgent(.cursor, instance: instance)
        case .antigravity: return runningAgent(.antigravity, instance: instance)
        case .opencode: return runningAgent(.opencode, instance: instance)
        case .download:
            return NotchIndicator(
                id: "download-\(instance)",
                content: .runningDownload(percentage: 42),
                accessibilityLabel: "Download 42 percent complete"
            )
        case .mediaPlayback:
            return NotchIndicator(
                id: "media-playback",
                content: .mediaPlayback(.init(id: "preview", title: "Sample track", artist: "Pulse Notch", duration: 180, elapsedTime: 42, isPlaying: true)),
                accessibilityLabel: "Sample track playing"
            )
        case .clock:
            return NotchIndicator(
                id: "clock-preview",
                content: .clock(ClockStatus(mode: .timer, time: 4 * 60 + 32, isRunning: true)),
                accessibilityLabel: "Timer, 4 minutes, 32 seconds, running"
            )
        }
    }

    private func runningAgent(_ kind: CodingAgentKind, instance: Int) -> NotchIndicator {
        NotchIndicator(id: "\(rawValue)-\(instance)", content: .runningAgent(kind), accessibilityLabel: "\(kind.displayName) agent running")
    }

    func testingCalendarEvent(instance: Int, at date: Date) -> CalendarEvent? {
        guard self == .calendar else { return nil }
        let startsAt = date.addingTimeInterval(31 * 60)
        return CalendarEvent(
            id: "testing-calendar-\(instance)",
            title: "Testing event",
            startsAt: startsAt,
            endsAt: startsAt.addingTimeInterval(60 * 60),
            calendarName: "Pulse Notch Testing",
            calendarColor: .orange
        )
    }

    func testingAgentSession(instance: Int, at date: Date) -> CodingAgentSession? {
        let kind: CodingAgentKind
        switch self {
        case .codex: kind = .codex
        case .claude: kind = .claude
        case .cursor: kind = .cursor
        case .antigravity: kind = .antigravity
        case .opencode: kind = .opencode
        default: return nil
        }

        return CodingAgentSession(
            id: "testing-\(rawValue)-\(instance)",
            kind: kind,
            title: "Testing session",
            detectedAt: date,
            workingDirectory: "/tmp/pulse-notch-testing",
            gitBranch: "testing",
            startedAt: date.addingTimeInterval(-5 * 60),
            status: .running
        )
    }

    func testingActionSession(instance: Int, at date: Date) -> GitHubActionSession? {
        guard self == .githubActions else { return nil }
        let run = GitHubActionRun(
            id: "testing-action-\(instance)",
            repository: "pulse-notch/pulse-notch",
            name: "Testing workflow",
            event: "workflow_dispatch",
            ref: "testing",
            url: URL(string: "https://github.com/pulse-notch/pulse-notch/actions"),
            updatedAt: date,
            status: .running
        )
        return GitHubActionSession(run: run, detectedAt: date, status: .running)
    }

    func testingDownload(instance: Int) -> DetectedDownload? {
        guard self == .download else { return nil }
        return DetectedDownload(
            id: "/tmp/pulse-notch-testing/download-\(instance).zip",
            byteCount: 42 * 1_024 * 1_024,
            totalByteCount: 100 * 1_024 * 1_024
        )
    }

    func testingPlayback() -> MediaPlaybackStatus? {
        guard self == .mediaPlayback else { return nil }
        return MediaPlaybackStatus(
            id: "testing-playback",
            title: "Testing track",
            artist: "Pulse Notch",
            duration: 180,
            elapsedTime: 42,
            isPlaying: true
        )
    }

    func testingClockStatus() -> ClockStatus? {
        guard self == .clock else { return nil }
        return ClockStatus(mode: .timer, time: 4 * 60 + 32, isRunning: true)
    }
}

enum CollapsedNotchIndicators {
    static func make(
        schedule: CalendarEventSchedule?,
        sessions: [CodingAgentSession],
        actionSessions: [GitHubActionSession],
        downloads: [DetectedDownload] = [],
        mediaPlayback: MediaPlaybackStatus? = nil,
        clock: ClockStatus? = nil,
        at date: Date,
        calendarReminderLeadTime: TimeInterval
    ) -> [NotchIndicator] {
        var indicators: [NotchIndicator] = []

        if let clock, clock.isRunning {
            indicators.append(NotchIndicator(id: "clock", content: .clock(clock), accessibilityLabel: clock.accessibilityLabel))
        }

        if let mediaPlayback, mediaPlayback.isPlaying {
            indicators.append(
                NotchIndicator(
                    id: "media-\(mediaPlayback.id)",
                    content: .mediaPlayback(mediaPlayback),
                    accessibilityLabel: "\(mediaPlayback.title)\(mediaPlayback.artist.isEmpty ? "" : " by \(mediaPlayback.artist)")\(mediaPlayback.isPlaying ? " playing" : " paused")"
                )
            )
        }

        if let event = schedule?.next(after: date), event.startsSoon(
            relativeTo: date,
            threshold: calendarReminderLeadTime
        ) {
            let minutesUntilStart = max(1, Int((event.startsAt.timeIntervalSince(date) / 60).rounded(.up)))
            indicators.append(
                NotchIndicator(
                    id: "calendar-\(event.id)",
                    content: .upcomingCalendarEvent(minutesUntilStart: minutesUntilStart),
                    accessibilityLabel: "Next calendar event starts in \(minutesUntilStart) \(minutesUntilStart == 1 ? "minute" : "minutes")"
                )
            )
        }

        if actionSessions.contains(where: { $0.status == .running }) {
            indicators.append(
                NotchIndicator(
                    id: "github-actions-running",
                    content: .githubActions(.running),
                    accessibilityLabel: "GitHub Actions running"
                )
            )
        } else if actionSessions.contains(where: {
            if case let .completed(status) = $0.status { return status == .failed }
            return false
        }) {
            indicators.append(
                NotchIndicator(
                    id: "github-actions-failed",
                    content: .githubActions(.failed),
                    accessibilityLabel: "GitHub Actions failed"
                )
            )
        }

        indicators.append(contentsOf: downloads.map { download in
            NotchIndicator(
                id: "download-\(download.id)",
                content: .runningDownload(percentage: download.percentage),
                accessibilityLabel: download.source == .homebrew
                    ? "Homebrew activity in progress"
                    : download.percentage.map { "Download \($0) percent complete" } ?? "Download in progress"
            )
        })

        indicators.append(contentsOf: sessions.map { session in
            let isRunning = session.status == .running
            return NotchIndicator(
                id: session.id,
                content: isRunning
                    ? .runningAgent(session.kind)
                    : .completedAgent(session.kind),
                accessibilityLabel: "\(session.kind.displayName) agent \(isRunning ? "running" : "completed")"
            )
        })

        return indicators
    }

    static func prioritize(
        _ indicators: [NotchIndicator],
        using categories: [CollapsedNotchIndicatorCategory]
    ) -> [NotchIndicator] {
        let ranks = Dictionary(uniqueKeysWithValues: categories.enumerated().map { ($1, $0) })
        return indicators.enumerated().sorted {
            let leftRank = ranks[$0.element.category] ?? categories.count
            let rightRank = ranks[$1.element.category] ?? categories.count
            return leftRank == rightRank ? $0.offset < $1.offset : leftRank < rightRank
        }.map(\.element)
    }
}

struct CollapsedNotchLayout {
    struct Level {
        let left: NotchIndicator?
        let right: NotchIndicator?

        var width: CGFloat {
            max(left.map(itemWidth) ?? 0, right.map(itemWidth) ?? 0)
        }

        private func itemWidth(_ indicator: NotchIndicator) -> CGFloat {
            switch indicator.content {
            case .upcomingCalendarEvent: 28
            case .runningDownload: 34
            case .mediaPlayback: 22
            case .clock: 48
            default: 16
            }
        }
    }

    let levels: [Level]

    init(indicators: [NotchIndicator], maximumPerSide: Int) {
        var levels: [Level] = []
        var index = 0
        var placeUnpairedOnLeft = true

        while index < indicators.count, levels.count < maximumPerSide {
            let indicator = indicators[index]
            if indicator.occupiesBothSides {
                levels.append(Level(left: indicator, right: indicator))
                index += 1
            } else if indicators[safe: index + 1]?.occupiesBothSides == false {
                levels.append(Level(left: indicator, right: indicators[index + 1]))
                index += 2
            } else {
                levels.append(Level(
                    left: placeUnpairedOnLeft ? indicator : nil,
                    right: placeUnpairedOnLeft ? nil : indicator
                ))
                placeUnpairedOnLeft.toggle()
                index += 1
            }
        }

        self.levels = levels
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

struct NotchIndicatorView: View {
    let indicator: NotchIndicator
    let reduceMotion: Bool
    var colorOverride: Color? = nil

    private var color: Color { colorOverride ?? indicator.color }

    var body: some View {
        Group {
            switch indicator.content {
            case let .upcomingCalendarEvent(minutesUntilStart):
                CalendarCountdownIndicator(
                    minutesUntilStart: minutesUntilStart,
                    color: color,
                    reduceMotion: reduceMotion
                )
            case .runningAgent:
                AgentActivityOrbit(color: color, reduceMotion: reduceMotion)
            case .completedAgent:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                    .symbolEffect(.bounce, value: indicator.content)
            case let .runningDownload(percentage):
                DownloadCollapsedIndicator(percentage: percentage, color: color, reduceMotion: reduceMotion)
            case let .githubActions(status):
                GitHubActionIndicator(status: status, color: color, reduceMotion: reduceMotion)
            case let .mediaPlayback(playback):
                MediaEqualizer(isPlaying: playback.isPlaying, reduceMotion: reduceMotion)
                    .foregroundStyle(color)
            case let .clock(status):
                ClockCollapsedIndicator(status: status, color: color, reduceMotion: reduceMotion)
            }
        }
            .accessibilityLabel(indicator.accessibilityLabel)
    }
}

struct ClockCollapsedIndicator: View {
    let status: ClockStatus
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        HStack {
            Image(systemName: status.mode.symbolName)
                .font(.system(size: 15, weight: .semibold))
            Spacer(minLength: 0)
            ClockCollapsedValue(status: status, reduceMotion: reduceMotion)
        }
        .foregroundStyle(color)
    }
}

struct ClockCollapsedValue: View {
    let status: ClockStatus
    let reduceMotion: Bool

    var body: some View {
        Text(ClockTimeFormatter.display(status.time))
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText())
            .fixedSize()
    }
}

struct CalendarCountdownIndicator: View {
    let minutesUntilStart: Int
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        HStack {
            CalendarCountdownIcon(color: color)
            Spacer(minLength: 0)
            CalendarCountdownValue(minutesUntilStart: minutesUntilStart, reduceMotion: reduceMotion)
        }
        .foregroundStyle(color)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: minutesUntilStart)
    }
}

struct CalendarCountdownIcon: View {
    let color: Color

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "calendar")
                .font(.system(size: 15, weight: .semibold))
            Image(systemName: "clock.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.black)
                .padding(1)
                .background(color, in: Circle())
                .offset(x: 2, y: 2)
        }
        .frame(height: 17)
        .foregroundStyle(color)
    }
}

struct CalendarCountdownValue: View {
    let minutesUntilStart: Int
    let reduceMotion: Bool

    var body: some View {
        Text("\(minutesUntilStart)m")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .contentTransition(reduceMotion ? .identity : .numericText())
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct AgentMark: View {
    let kind: CodingAgentKind
    let size: CGFloat

    var body: some View {
        Group {
            if let iconURL, let image = NSImage(contentsOf: iconURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var iconURL: URL? {
        AgentIconResource.url(for: kind)
    }
}

enum AgentIconResource {
    static func url(
        for kind: CodingAgentKind,
        resourceDirectory: URL? = Bundle.main.resourceURL
    ) -> URL? {
        resourceDirectory?
            .appendingPathComponent("PulseNotch_PulseNotchApp.bundle", isDirectory: true)
            .appendingPathComponent(kind.rawValue)
            .appendingPathExtension("png")
    }
}

private struct AgentActivityOrbit: View {
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            orbit(progress: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                orbit(progress: context.date.timeIntervalSinceReferenceDate / 1.4)
            }
        }
    }

    private func orbit(progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.3), lineWidth: 1.3)
            Circle()
                .fill(color)
                .frame(width: 3.5, height: 3.5)
                .offset(y: -5.2)
                .rotationEffect(.degrees(progress * 360))
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

struct DownloadActivityIndicator: View {
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    Circle()
                        .fill(color)
                        .frame(width: 3, height: 3)
                        .offset(y: -7)
                        .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 300))
                }
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

struct DownloadProgressValue: View {
    let percentage: Int?
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        Text(percentage.map { "\($0)%" } ?? "—")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .fixedSize()
    }
}

struct DownloadCollapsedIndicator: View {
    let percentage: Int?
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        HStack {
            DownloadProgressValue(percentage: percentage, color: color, reduceMotion: reduceMotion)
            Spacer(minLength: 0)
            DownloadActivityIndicator(color: color, reduceMotion: reduceMotion)
        }
    }
}

private struct GitHubActionIndicator: View {
    let status: GitHubPullRequest.ActionStatus
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        if status == .running, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                symbol(rotation: context.date.timeIntervalSinceReferenceDate / 1.6 * 360)
            }
        } else {
            symbol(rotation: 0)
        }
    }

    private func symbol(rotation: Double) -> some View {
        Image(systemName: symbolName)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(color)
            .rotationEffect(.degrees(rotation))
            .accessibilityHidden(true)
    }

    private var symbolName: String {
        switch status {
        case .running: "arrow.triangle.2.circlepath"
        case .failed: "xmark.octagon.fill"
        case .succeeded: "checkmark.circle.fill"
        case .none: "minus.circle"
        }
    }
}
