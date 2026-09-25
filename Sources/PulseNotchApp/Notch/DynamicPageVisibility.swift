struct DynamicPageActivity: Equatable {
    let calendar: Bool
    let agents: Bool
    let agentUsage: Bool
    let github: Bool
    let media: Bool
    let clock: Bool
    let downloads: Bool
    /// The AI Agent page stays reachable whenever the feature is enabled, even while idle.
    let aiAgent: Bool

    init(
        calendar: Bool,
        agents: Bool,
        agentUsage: Bool = false,
        github: Bool,
        media: Bool,
        clock: Bool = false,
        downloads: Bool = false,
        aiAgent: Bool = false
    ) {
        self.calendar = calendar
        self.agents = agents
        self.agentUsage = agentUsage
        self.github = github
        self.media = media
        self.clock = clock
        self.downloads = downloads
        self.aiAgent = aiAgent
    }

    func visiblePages(from configuredPages: [NotchPage], isEnabled: Bool) -> [NotchPage] {
        guard isEnabled else { return configuredPages }
        return configuredPages.filter(isActive)
    }

    private func isActive(_ page: NotchPage) -> Bool {
        switch page {
        case .summary: true
        case .calendar: calendar
        case .agents: agents || agentUsage
        case .github: github
        case .media: media
        case .clock: clock
        case .downloads: downloads
        case .aiAgent: aiAgent
        }
    }
}
