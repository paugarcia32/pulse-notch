import PulseNotchCore
import SwiftUI

struct GitHubPage: View {
    @ObservedObject var model: GitHubFeatureModel
    let date: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                placeholder { ProgressView().controlSize(.small) }
            case let .loaded(pullRequests):
                content(pullRequests)
            case .unavailable:
                placeholder {
                    Label("GitHub is unavailable — sign in with gh auth login", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func content(_ pullRequests: [GitHubPullRequest]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader(pullRequests)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 7) {
                    runningActions(model.actionSessions)
                    if pullRequests.isEmpty {
                        emptyState
                    } else {
                        ForEach(pullRequests) { pullRequest in row(pullRequest) }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sectionHeader(_ pullRequests: [GitHubPullRequest]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("GITHUB")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.pink)
            Spacer(minLength: 6)
            Text(pullRequests.isEmpty ? "All caught up" : "\(pullRequests.count) open")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("No open pull requests created by you")
                .font(.callout.weight(.semibold))
            Text("You are all caught up")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity)
    }

    private func row(_ pullRequest: GitHubPullRequest) -> some View {
        HStack(spacing: 10) {
            pullRequestIcon(pullRequest)
                .frame(width: 24, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(pullRequest.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text("\(pullRequest.repository) #\(pullRequest.number)")
                    Label("\(pullRequest.commentCount)", systemImage: "bubble.left")
                    Label("\(pullRequest.passedCheckCount)", systemImage: "checkmark.circle")
                    Text(pullRequest.reviewStatusLabel)
                        .foregroundStyle(pullRequest.reviewStatusColor)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { openURL(pullRequest.url) } label: {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open pull request \(pullRequest.title) in GitHub")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func pullRequestIcon(_ pullRequest: GitHubPullRequest) -> some View {
        switch pullRequest.actionStatus {
        case .none:
            Image(systemName: pullRequest.isDraft ? "arrow.triangle.branch" : "arrow.triangle.pull")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(pullRequest.reviewStatusColor)
                .accessibilityLabel(pullRequest.reviewStatusLabel)
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
    private func runningActions(_ sessions: [GitHubActionSession]) -> some View {
        let running = sessions.filter { $0.status == .running }
        if !running.isEmpty {
            ForEach(running) { session in
                HStack(spacing: 8) {
                    NotchIndicatorView(
                        indicator: NotchIndicator(
                            id: session.id,
                            content: .githubActions(.running),
                            accessibilityLabel: "GitHub Action running"
                        ),
                        reduceMotion: reduceMotion
                    )
                    Text(session.runner.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("#\(session.runner.pullRequestNumber)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
            }
        }
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
}

private extension GitHubPullRequest {
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
