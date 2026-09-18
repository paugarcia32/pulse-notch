struct DynamicPageActivity: Equatable {
    let calendar: Bool
    let agents: Bool
    let github: Bool
    let media: Bool

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
        }
    }
}
