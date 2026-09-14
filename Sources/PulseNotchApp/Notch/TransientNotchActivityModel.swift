import PulseNotchCore
import Combine

@MainActor
final class TransientNotchActivityModel: ObservableObject {
    @Published private(set) var activity: TransientNotchActivity?

    private var dismissalTask: Task<Void, Never>?

    func show(_ activity: TransientNotchActivity) {
        self.activity = activity
        dismissalTask?.cancel()
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.activity = nil
        }
    }

    func dismiss() {
        dismissalTask?.cancel()
        activity = nil
    }

    deinit { dismissalTask?.cancel() }
}
