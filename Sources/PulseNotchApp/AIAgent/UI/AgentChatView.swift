import PulseNotchCore
import SwiftUI

struct AgentChatView: View {
    @ObservedObject var model: AIAgentFeatureModel
    /// False while the notch is collapsed or another page is shown.
    let isActive: Bool
    @FocusState private var composerFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            conversationBar
            let issues = model.setupIssues()
            if !issues.isEmpty {
                AgentBanner(text: issues.joined(separator: "\n"), symbol: "wrench.and.screwdriver", tint: .blue)
                    .onTapGesture { model.selectedTab = .settings }
                    .accessibilityHint("Opens AI Agent settings")
            }
            transcript
            if let live = model.selectedConversationRun {
                VStack(alignment: .leading, spacing: 4) {
                    RunControls(model: model, live: live)
                    ActionTimeline(events: live.run.events)
                }
                .agentTile(contrast: contrast)
            }
            composer
        }
    }

    private var conversationBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("New conversation") { model.newConversation() }
                if !model.conversations.isEmpty { Divider() }
                ForEach(model.conversations.prefix(30)) { conversation in
                    Button(conversation.title) {
                        Task { try? await model.selectConversation(conversation.id) }
                    }
                }
            } label: {
                Label(currentTitle, systemImage: "text.bubble")
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
            Button {
                model.newConversation()
                composerFocused = true
            } label: {
                Label("New conversation", systemImage: "square.and.pencil")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            if let id = model.selectedConversationID {
                Button(role: .destructive) {
                    Task { await model.deleteConversation(id) }
                } label: {
                    Label("Delete conversation", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        .font(.caption)
    }

    private var currentTitle: String {
        model.conversations.first { $0.id == model.selectedConversationID }?.title ?? "New conversation"
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if model.chatEntries.isEmpty && model.selectedConversationRun == nil {
                        emptyState
                    }
                    ForEach(model.chatEntries) { entry in
                        message(role: entry.role, text: entry.text)
                            .id(entry.id)
                    }
                    if let live = model.selectedConversationRun, !live.streamingText.isEmpty {
                        message(role: .assistant, text: live.streamingText)
                            .id("streaming")
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: model.chatEntries.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: model.selectedConversationRun?.streamingText) { _, _ in scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        let target: AnyHashable? = model.selectedConversationRun?.streamingText.isEmpty == false
            ? AnyHashable("streaming")
            : model.chatEntries.last.map { AnyHashable($0.id) }
        guard let target else { return }
        if reduceMotion {
            proxy.scrollTo(target, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .bottom) }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "brain")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Ask the agent or give it a task").font(.callout.weight(.semibold))
            Text("For example: “Open TextEdit and write a shopping list.” The agent works autonomously within your settings; Stop is always available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .agentTile(contrast: contrast)
        .accessibilityElement(children: .combine)
    }

    private func message(role: ChatRole, text: String) -> some View {
        let isUser = role == .user
        return HStack {
            if isUser { Spacer(minLength: 60) }
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    isUser ? Color.accentColor.opacity(0.35) : .white.opacity(contrast == .increased ? 0.14 : 0.08),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .accessibilityLabel("\(isUser ? "You" : "Agent"): \(text)")
            if !isUser { Spacer(minLength: 60) }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(composerPrompt, text: $model.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($composerFocused)
                .onSubmit { send() }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(contrast == .increased ? 0.16 : 0.1), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Message the AI Agent")
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)
            .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.selectedConversationRun?.isExecuting == true)
            .accessibilityLabel("Send")
            .keyboardShortcut(.return, modifiers: .command)
        }
        // While the composer is focused, desktop input pauses so the agent never
        // types into its own interface.
        .onChange(of: composerFocused) { _, focused in model.setComposerFocused(focused && isActive) }
        .onChange(of: isActive) { _, active in model.setComposerFocused(composerFocused && active) }
        .onDisappear { model.setComposerFocused(false) }
    }

    private var composerPrompt: String {
        if case .needsInput = model.selectedConversationRun?.run.status { return "Reply to continue…" }
        return "Message the agent…"
    }

    private func send() {
        // Release the composer so the run can use the keyboard in other apps.
        composerFocused = false
        Task { await model.sendDraft() }
    }
}
