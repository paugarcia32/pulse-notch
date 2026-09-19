import Combine
import Foundation

struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(_ value: String) {
        let normalized = value.first == "v" ? String(value.dropFirst()) : value
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)

        guard components.count == 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]),
              major >= 0,
              minor >= 0,
              patch >= 0 else {
            return nil
        }

        self.init(major: major, minor: minor, patch: patch)
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}

struct AppRelease: Equatable, Sendable {
    let version: AppVersion
    let pageURL: URL
}

protocol AppReleaseProviding: Sendable {
    func latestRelease() async throws -> AppRelease
}

struct GitHubReleaseProvider: AppReleaseProviding {
    private struct ReleaseResponse: Decodable {
        let tagName: String
        let pageURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case pageURL = "html_url"
        }
    }

    private enum ReleaseError: Error {
        case invalidResponse
        case invalidVersion
    }

    private let session: URLSession
    private let latestReleaseURL: URL

    init(
        session: URLSession = .shared,
        latestReleaseURL: URL = URL(
            string: "https://api.github.com/repos/paugarcia32/pulse-notch/releases/latest"
        )!
    ) {
        self.session = session
        self.latestReleaseURL = latestReleaseURL
    }

    func latestRelease() async throws -> AppRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PulseNotch", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ReleaseError.invalidResponse
        }

        return try Self.release(from: data)
    }

    static func release(from data: Data) throws -> AppRelease {
        let response = try JSONDecoder().decode(ReleaseResponse.self, from: data)
        guard let version = AppVersion(response.tagName) else {
            throw ReleaseError.invalidVersion
        }
        return AppRelease(version: version, pageURL: response.pageURL)
    }
}

@MainActor
final class UpdateFeatureModel: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case failed
    }

    @Published private(set) var state: State = .idle
    @Published var automaticChecksEnabled: Bool {
        didSet {
            defaults.set(automaticChecksEnabled, forKey: automaticChecksEnabledKey)
        }
    }

    let currentVersion: AppVersion

    private let provider: any AppReleaseProviding
    private let defaults: UserDefaults
    private let automaticChecksEnabledKey = "updates.automaticChecksEnabled"
    private let lastCheckDateKey = "updates.lastCheckDate"
    private let automaticCheckInterval: TimeInterval = 24 * 60 * 60
    private var checkTask: Task<Void, Never>?

    init(
        provider: any AppReleaseProviding,
        currentVersion: AppVersion,
        defaults: UserDefaults = .standard
    ) {
        self.provider = provider
        self.currentVersion = currentVersion
        self.defaults = defaults
        automaticChecksEnabled = defaults.object(forKey: automaticChecksEnabledKey) as? Bool ?? true
    }

    var availableRelease: AppRelease? {
        guard case let .available(release) = state else {
            return nil
        }
        return release
    }

    func startAutomaticCheck(at date: Date = .now) {
        startCheck(force: false, at: date)
    }

    func checkNow(at date: Date = .now) {
        startCheck(force: true, at: date)
    }

    func cancel() {
        checkTask?.cancel()
        checkTask = nil
    }

    func refresh(force: Bool, at date: Date) async {
        guard force || shouldRunAutomaticCheck(at: date) else {
            return
        }

        let previousState = state
        state = .checking
        defaults.set(date, forKey: lastCheckDateKey)

        do {
            let release = try await provider.latestRelease()
            try Task.checkCancellation()
            state = release.version > currentVersion ? .available(release) : .upToDate
        } catch is CancellationError {
            state = previousState
        } catch {
            state = .failed
        }
    }

    private func startCheck(force: Bool, at date: Date) {
        guard checkTask == nil else {
            return
        }

        checkTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.refresh(force: force, at: date)
            self.checkTask = nil
        }
    }

    private func shouldRunAutomaticCheck(at date: Date) -> Bool {
        guard automaticChecksEnabled else {
            return false
        }
        guard let lastCheckDate = defaults.object(forKey: lastCheckDateKey) as? Date else {
            return true
        }
        return date.timeIntervalSince(lastCheckDate) >= automaticCheckInterval
    }
}
