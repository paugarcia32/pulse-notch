struct DynamicPageActivity: Equatable {
    let calendar: Bool
    let agents: Bool
    let github: Bool
    let media: Bool
    let clock: Bool
    let downloads: Bool

    init(
        calendar: Bool,
        agents: Bool,
        github: Bool,
        media: Bool,
        clock: Bool = false,
        downloads: Bool = false
    ) {
        self.calendar = calendar
        self.agents = agents
        self.github = github
        self.media = media
        self.clock = clock
        self.downloads = downloads
    }

    func visiblePages(from configuredPages: [NotchPage], isEnabled: Bool) -> [NotchPage] {
        guard isEnabled else { return configuredPages }
        return configuredPages.filter(isActive)
    }

    private func isActive(_ page: NotchPage) -> Bool {
        switch page {
        case .summary: true
        case .calendar: calendar
        case .agents: agents
        case .github: github
        case .media: media
        case .clock: clock
        case .downloads: downloads
        }
    }
}
