import PulseNotchCore
import SwiftUI

struct GitHubPage: View {
    @ObservedObject var model: GitHubFeatureModel
    let date: Date

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub").font(.headline)
            Divider()
            switch model.state {
            case .loading:
                ProgressView().controlSize(.small)
            case let .loaded(pullRequests):
                content(pullRequests)
            case .unavailable:
                Label("GitHub is unavailable — sign in with gh auth login", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func content(_ pullRequests: [GitHubPullRequest]) -> some View {
        if pullRequests.isEmpty {
            Label("No open pull requests created by you", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(pullRequests) { pullRequest in row(pullRequest) }
                    runners(model.actionSessions)
                }
            }
        }
    }

    private func row(_ pullRequest: GitHubPullRequest) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
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
            Spacer(minLength: 8)
            Label(pullRequest.statusLabel.uppercased(), systemImage: pullRequest.statusImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(pullRequest.statusColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(pullRequest.statusColor.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(pullRequest.statusColor.opacity(0.35), lineWidth: 0.5))
            Button { openURL(pullRequest.url) } label: { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(.plain)
                .accessibilityLabel("Open pull request \(pullRequest.title) in GitHub")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func runners(_ sessions: [GitHubActionSession]) -> some View {
        if !sessions.isEmpty {
            Divider().padding(.vertical, 4)
            Label("Runners", systemImage: "cpu")
                .font(.caption.weight(.semibold))
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
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            }
        }
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
