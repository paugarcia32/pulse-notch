import PulseNotchCore
import SwiftUI

struct GitHubPage: View {
    @ObservedObject var model: GitHubFeatureModel
    let date: Date
    let testingPullRequests: [GitHubPullRequest]?
    let testingActionSessions: [GitHubActionSession]?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.openURL) private var openURL

    init(
        model: GitHubFeatureModel,
        date: Date,
        testingPullRequests: [GitHubPullRequest]? = nil,
        testingActionSessions: [GitHubActionSession]? = nil
    ) {
        self.model = model
        self.date = date
        self.testingPullRequests = testingPullRequests
        self.testingActionSessions = testingActionSessions
    }

    var body: some View {
        Group {
            switch testingPullRequests.map(GitHubFeatureModel.State.loaded)
                ?? (testingActionSessions == nil ? model.state : .loaded([])) {
            case .loading:
                placeholder { ProgressView().controlSize(.small) }
            case let .loaded(pullRequests):
                content(pullRequests)
            case let .unavailable(reason):
                placeholder {
                    Label(unavailableMessage(reason), systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func content(_ pullRequests: [GitHubPullRequest]) -> some View {
        let running = (testingActionSessions ?? model.actionSessions).filter { $0.status == .running }
        return VStack(alignment: .leading, spacing: 9) {
            sectionHeader(pullRequests: pullRequests.count, running: running.count)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if !running.isEmpty {
                        sectionLabel("RUNNING ACTIONS")
                        ForEach(running) { actionRow($0) }
                    }
                    if !pullRequests.isEmpty {
                        sectionLabel("PULL REQUESTS")
                        ForEach(pullRequests) { pullRequestRow($0) }
                    }
                    if running.isEmpty && pullRequests.isEmpty {
                        emptyState
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var tileFill: Color { .white.opacity(contrast == .increased ? 0.14 : 0.08) }

    private func sectionHeader(pullRequests: Int, running: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("GITHUB")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(Self.activityDescription(pullRequests: pullRequests, running: running))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(height: 16)
    }

    static func activityDescription(pullRequests: Int, running: Int) -> String {
        let parts = [
            pullRequests > 0 ? "\(pullRequests) open" : nil,
            running > 0 ? "\(running) running" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "All caught up" : parts.joined(separator: " · ")
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No open pull requests created by you")
                .font(.callout.weight(.semibold))
            Text("No Actions running either")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func pullRequestRow(_ pullRequest: GitHubPullRequest) -> some View {
        Button { openURL(pullRequest.url) } label: {
            HStack(spacing: 10) {
                pullRequestIcon(pullRequest)
                    .frame(width: 30, height: 30)
                    .background(pullRequest.statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pullRequest.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("\(pullRequest.repository) #\(pullRequest.number)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(pullRequest.statusLabel)
                            .foregroundStyle(pullRequest.statusColor)
                            .fixedSize()
                    }
                    .font(.caption2.weight(.medium))
                }
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tileFill, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open pull request \(pullRequest.title), \(pullRequest.repository) number \(pullRequest.number), \(pullRequest.statusLabel), \(pullRequest.commentCount) comments, \(pullRequest.passedCheckCount) passed checks, in GitHub")
    }

    @ViewBuilder
    private func pullRequestIcon(_ pullRequest: GitHubPullRequest) -> some View {
        switch pullRequest.actionStatus {
        case .none:
            Image(systemName: pullRequest.isDraft ? "arrow.triangle.branch" : "arrow.triangle.pull")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(pullRequest.statusColor)
        case let status:
            NotchIndicatorView(
                indicator: NotchIndicator(
                    id: pullRequest.id,
                    content: .githubActions(status),
                    accessibilityLabel: actionAccessibilityLabel(status)
                ),
                reduceMotion: reduceMotion
            )
        }
    }

    @ViewBuilder
    private func actionRow(_ session: GitHubActionSession) -> some View {
        if let url = session.run.url {
            Button { openURL(url) } label: { actionContent(session, showsLink: true) }
                .buttonStyle(.plain)
                .accessibilityLabel("Open running GitHub Action \(session.run.name), \(actionContext(session.run)), in GitHub")
        } else {
            actionContent(session, showsLink: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("GitHub Action \(session.run.name) running, \(actionContext(session.run))")
        }
    }

    private func actionContent(_ session: GitHubActionSession, showsLink: Bool) -> some View {
        HStack(spacing: 10) {
            NotchIndicatorView(
                indicator: NotchIndicator(
                    id: session.id,
                    content: .githubActions(.running),
                    accessibilityLabel: "GitHub Action running"
                ),
                reduceMotion: reduceMotion
            )
            .frame(width: 30, height: 30)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.run.name).font(.callout.weight(.semibold)).lineLimit(1)
                Text(actionContext(session.run)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if showsLink {
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub").font(.headline)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func actionAccessibilityLabel(_ status: GitHubPullRequest.ActionStatus) -> String {
        switch status {
        case .running: "GitHub Actions running"
        case .failed: "GitHub Actions failed"
        case .succeeded: "GitHub Actions passed"
        case .none: "No GitHub Actions"
        }
    }

    private func actionContext(_ run: GitHubActionRun) -> String {
        let context = run.pullRequestNumber.map { "#\($0)" } ?? run.ref
        return [run.repository, context].compactMap { $0 }.joined(separator: " · ")
    }

    private func unavailableMessage(_ reason: GitHubFeatureModel.State.Reason) -> String {
        switch reason {
        case .commandLineToolMissing:
            "GitHub CLI was not found — install gh with Homebrew"
        case .requestFailed:
            "GitHub is unavailable — verify gh authentication and repository access"
        }
    }
}

private extension GitHubPullRequest {
    var statusLabel: String {
        if case .failed = actionStatus { return "Checks failed" }
        return reviewStatusLabel
    }

    var statusColor: Color {
        if case .failed = actionStatus { return .red }
        return reviewStatusColor
    }

    var reviewStatusLabel: String {
        if isDraft { return "Draft" }
        return switch reviewStatus {
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        case .awaitingReview: "Awaiting review"
        }
    }

    var reviewStatusColor: Color {
        if isDraft { return .secondary }
        return switch reviewStatus {
        case .approved: .green
        case .changesRequested: .red
        case .awaitingReview: .orange
        }
    }
}
