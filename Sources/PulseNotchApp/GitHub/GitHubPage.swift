import PulseNotchCore
import SwiftUI

struct GitHubPage: View {
    @ObservedObject var model: GitHubFeatureModel
    let date: Date

    @Environment(\.openURL) private var openURL

    var body: some View {
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

    private func content(_ pullRequests: [GitHubPullRequest]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(pullRequests)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if pullRequests.isEmpty {
                        emptyState
                    } else {
                        ForEach(pullRequests) { pullRequest in row(pullRequest) }
                    }
                    runners(model.actionSessions)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ pullRequests: [GitHubPullRequest]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("GITHUB")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.pink)
            Text(pullRequests.isEmpty ? "All caught up" : "\(pullRequests.count) open \(pullRequests.count == 1 ? "pull request" : "pull requests")")
                .font(.title3.weight(.semibold))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("No open pull requests").font(.title3.weight(.semibold))
            Text("Your review queue is clear").font(.callout).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func row(_ pullRequest: GitHubPullRequest) -> some View {
        HStack(spacing: 9) {
            Capsule()
                .fill(pullRequest.statusColor)
                .frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(pullRequest.repository.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(pullRequest.title).font(.callout.weight(.semibold)).lineLimit(1)
                HStack(spacing: 8) {
                    Text("#\(pullRequest.number)")
                    Label("\(pullRequest.commentCount)", systemImage: "bubble.left")
                    Label("\(pullRequest.passedCheckCount)", systemImage: "checkmark.circle")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(pullRequest.commentCount) comments, \(pullRequest.passedCheckCount) checks passed")
            }
            Spacer(minLength: 4)
            Image(systemName: pullRequest.statusImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(pullRequest.statusColor)
            Button { openURL(pullRequest.url) } label: { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Open pull request \(pullRequest.title) in GitHub")
        }
        .padding(9)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func runners(_ sessions: [GitHubActionSession]) -> some View {
        if !sessions.isEmpty {
            Text("WORKFLOWS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            ForEach(sessions) { session in
                HStack(spacing: 10) {
                    Image(systemName: session.status == .running ? "arrow.triangle.2.circlepath" : "cpu")
                        .foregroundStyle(actionColor(session.actionStatus))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.runner.name).font(.callout.weight(.semibold)).lineLimit(1)
                        Text("#\(session.runner.pullRequestNumber) · \(actionLabel(session.actionStatus))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(9)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("GitHub").font(.headline)
            Divider()
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private extension GitHubActionSession {
    var actionStatus: GitHubPullRequest.ActionStatus {
        switch status {
        case .running: .running
        case let .completed(status): status
        }
    }
}

private extension GitHubPullRequest {
    var statusLabel: String {
        if isDraft { return "Draft" }
        return reviewStatus == .approved ? "Approved" : "Open"
    }

    var statusImage: String {
        if isDraft { return "arrow.triangle.branch" }
        return reviewStatus == .approved ? "checkmark.seal" : "arrow.triangle.pull"
    }

    var statusColor: Color {
        isDraft ? .white.opacity(0.82) : reviewStatus == .approved ? .green : .orange
    }
}

private func actionLabel(_ status: GitHubPullRequest.ActionStatus) -> String {
    switch status {
    case .none: return "No Actions"
    case .running: return "Running"
    case .failed: return "Failed"
    case let .succeeded(completedAt):
        guard let completedAt else { return "Passed" }
        return "Passed \(completedAt.formatted(.relative(presentation: .numeric)))"
    }
}

private func actionColor(_ status: GitHubPullRequest.ActionStatus) -> Color {
    switch status {
    case .failed: .red
    case .running: .orange
    case .succeeded: .green
    case .none: .secondary
    }
}
