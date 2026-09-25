import Foundation

/// One concrete action the decision provider can choose for the current step.
public struct ActionCandidate: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case act(ProposedAction)
        /// The step is already accomplished on screen.
        case done
        /// No listed action advances the step.
        case abstain
    }

    public static let doneOption = "done: the step is visibly complete"
    public static let abstainOption = "blocked: no offered action makes progress"

    /// The option name sent to the decision provider. Laya weighs option names more
    /// than their descriptions, so the name itself describes the action.
    public let option: String
    public let description: String
    public let kind: Kind

    public init(option: String, description: String, kind: Kind) {
        self.option = option
        self.description = description
        self.kind = kind
    }
}

/// Builds the actions the decision provider chooses from, so JEV or Laya operates the
/// screen while the language model only describes each step.
public enum ActionCandidates {
    static let textInputRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    static let pressableRoles: Set<String> = [
        "AXButton", "AXLink", "AXMenuItem", "AXMenuButton", "AXMenuBarItem", "AXPopUpButton", "AXCheckBox",
        "AXRadioButton", "AXTab", "AXCell", "AXRow", "AXDisclosureTriangle", "AXIncrementor", "AXSegmentedControl"
    ]

    /// - Parameters:
    ///   - text: Text the step still has to type; `nil` once it has been typed.
    ///   - maximumControls: Upper bound on per-control candidates before context fitting.
    public static func build(
        for observation: Observation,
        step: String,
        text: String?,
        maximumControls: Int = 40
    ) -> [ActionCandidate] {
        var candidates: [ActionCandidate] = []
        func add(_ description: String, _ action: ProposedAction) {
            guard !candidates.contains(where: { $0.description == description }) else { return }
            candidates.append(ActionCandidate(option: description, description: description, kind: .act(action)))
        }

        let mentionsMenu = step.lowercased().contains("menu")
        let ranked = ElementShortlist.ranked(observation.elements, relevantTo: "\(step) \(text ?? "")")
            // Menu bars dominate native apps (121 of 147 elements in Calculator) and
            // drown out the window's own controls unless the step is about menus.
            .filter { $0.isEnabled && (mentionsMenu || !menuRoles.contains($0.role)) }
        var controls = 0
        for element in ranked where controls < maximumControls {
            let target = ActionTarget.element(id: element.id, observationID: observation.id)
            let name = "\(Self.roleName(element.role)) “\(element.label)”" + Self.currentValue(element)
            if textInputRoles.contains(element.role) {
                if let text { add("type into \(name)", .typeText(text, into: target)) }
                add("click \(name)", .click(target))
                controls += 1
            } else if pressableRoles.contains(element.role) || element.actions.contains("AXPress") {
                add("click \(name)", .click(target))
                controls += 1
            }
        }

        if let text { add("type at the current cursor", .typeText(text, into: nil)) }
        add("press Return", .pressKeys(KeyShortcut(key: "return")))
        add("press Tab", .pressKeys(KeyShortcut(key: "tab")))
        add("press Escape", .pressKeys(KeyShortcut(key: "escape")))
        add("scroll down", .scroll(.down, amount: 5, at: nil))
        add("scroll up", .scroll(.up, amount: 5, at: nil))
        candidates.append(ActionCandidate(option: ActionCandidate.doneOption, description: ActionCandidate.doneOption, kind: .done))
        candidates.append(ActionCandidate(option: ActionCandidate.abstainOption, description: ActionCandidate.abstainOption, kind: .abstain))
        return candidates
    }

    static let menuRoles: Set<String> = ["AXMenuBarItem", "AXMenuItem", "AXMenuBar", "AXMenu"]

    /// Web-style role names, which match the vocabulary decision models were trained on.
    static func roleName(_ role: String) -> String {
        switch role {
        case "AXTextArea", "AXTextField": "textbox"
        case "AXSearchField": "searchbox"
        case "AXComboBox", "AXPopUpButton": "combobox"
        case "AXMenuButton", "AXMenuBarItem": "menu"
        case "AXMenuItem": "menuitem"
        case "AXCheckBox": "checkbox"
        case "AXRadioButton": "radio"
        case "AXTab": "tab"
        case "AXCell", "AXRow": "row"
        case "AXLink": "link"
        case "AXSlider", "AXIncrementor": "slider"
        default: "button"
        }
    }

    /// Shows a field's current value so the decision model does not refill it.
    static func currentValue(_ element: AccessibleElement) -> String {
        guard let value = element.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return "" }
        return textInputRoles.contains(element.role) || element.role == "AXCheckBox" || element.role == "AXPopUpButton"
            ? " = “\(value.prefix(40))”"
            : ""
    }

    /// Identifies what is visibly on screen, to tell whether an action changed anything.
    public static func fingerprint(_ observation: Observation) -> Int {
        var hasher = Hasher()
        hasher.combine(observation.bundleID)
        hasher.combine(observation.windowTitle)
        for element in observation.elements {
            hasher.combine(element.role)
            hasher.combine(element.label)
            hasher.combine(element.value)
            hasher.combine(element.isEnabled)
        }
        return hasher.finalize()
    }

    /// Fits the choice question into the decision provider's context by dropping the
    /// least relevant control actions. The generic actions, `done`, and `abstain`
    /// always stay; if even they do not fit, the context is insufficient.
    public static func fit(
        _ candidates: [ActionCandidate],
        state: String,
        instructions: String,
        limit: Int,
        companionQuestions: [DecisionQuestion] = []
    ) -> (question: DecisionQuestion, included: [ActionCandidate])? {
        let companionCost = companionQuestions.map(TokenEstimator.estimate).max() ?? 0
        let controlCount = candidates.prefix { candidate in
            if case .act(let action) = candidate.kind, action.target != nil { return true }
            return false
        }.count
        let generic = Array(candidates.dropFirst(controlCount))
        var keep = controlCount
        while keep >= 0 {
            let included = Array(candidates.prefix(keep)) + generic
            let question = DecisionQuestion(
                id: "action",
                instructions: instructions,
                kind: .choice(included.map { DecisionOption($0.option) })
            )
            if TokenEstimator.estimate(state) + max(TokenEstimator.estimate(question), companionCost) <= limit {
                return (question, included)
            }
            keep -= keep > 8 ? max(1, keep / 4) : 1
        }
        return nil
    }
}
