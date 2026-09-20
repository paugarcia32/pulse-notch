import Foundation
import Testing
@testable import PulseNotchApp

@MainActor
struct UpdateFeatureModelTests {
    @Test
    func versionsParseReleaseTagsAndCompareNumerically() {
        #expect(AppVersion("v1.2.3") == AppVersion(major: 1, minor: 2, patch: 3))
        #expect(AppVersion("1.10.0")! > AppVersion("1.9.9")!)
        #expect(AppVersion("1.2") == nil)
        #expect(AppVersion("1.2.3-beta") == nil)
    }

    @Test
    func githubReleaseResponseDecodesTheTagAndPageURL() throws {
        let release = try GitHubReleaseProvider.release(from: Data("""
        {
          "tag_name": "v2.1.0",
          "html_url": "https://github.com/paugarcia32/pulse-notch/releases/tag/v2.1.0"
        }
        """.utf8))

        #expect(release.version == AppVersion(major: 2, minor: 1, patch: 0))
        #expect(release.pageURL.absoluteString.hasSuffix("/v2.1.0"))
    }

    @Test
    func newerReleaseBecomesAvailable() async {
        let provider = ReleaseProviderFake(
            release: AppRelease(
                version: AppVersion(major: 1, minor: 1, patch: 0),
                pageURL: URL(string: "https://example.com/release")!
            )
        )
        let defaults = makeDefaults()
        let model = UpdateFeatureModel(
            provider: provider,
            currentVersion: AppVersion(major: 1, minor: 0, patch: 0),
            defaults: defaults
        )

        await model.refresh(force: true, at: Date(timeIntervalSince1970: 1_000))

        #expect(model.state == .available(AppRelease(
            version: AppVersion(major: 1, minor: 1, patch: 0),
            pageURL: URL(string: "https://example.com/release")!
        )))
    }

    @Test
    func testingReleaseAppearsAsAnAvailableUpdate() {
        let model = UpdateFeatureModel(
            provider: ReleaseProviderFake(release: nil),
            currentVersion: AppVersion(major: 1, minor: 2, patch: 3),
            defaults: makeDefaults()
        )

        model.showTestingAvailableRelease()

        #expect(model.availableRelease?.version == AppVersion(major: 1, minor: 2, patch: 4))
        #expect(model.availableRelease?.pageURL.absoluteString == "https://github.com/paugarcia32/pulse-notch/releases")

        model.hideTestingAvailableRelease()

        #expect(model.state == .idle)
        #expect(!model.isTestingReleaseShown)
    }

    @Test
    func automaticChecksRunAtMostOncePerDay() async {
        let provider = ReleaseProviderFake(
            release: AppRelease(
                version: AppVersion(major: 1, minor: 0, patch: 0),
                pageURL: URL(string: "https://example.com/release")!
            )
        )
        let model = UpdateFeatureModel(
            provider: provider,
            currentVersion: AppVersion(major: 1, minor: 0, patch: 0),
            defaults: makeDefaults()
        )
        let start = Date(timeIntervalSince1970: 1_000)

        await model.refresh(force: false, at: start)
        await model.refresh(force: false, at: start.addingTimeInterval(60 * 60))
        #expect(await provider.requestCount == 1)

        await model.refresh(force: false, at: start.addingTimeInterval(24 * 60 * 60))
        #expect(await provider.requestCount == 2)
    }

    @Test
    func manualCheckWorksWhenAutomaticChecksAreDisabled() async {
        let provider = ReleaseProviderFake(
            release: AppRelease(
                version: AppVersion(major: 1, minor: 0, patch: 0),
                pageURL: URL(string: "https://example.com/release")!
            )
        )
        let model = UpdateFeatureModel(
            provider: provider,
            currentVersion: AppVersion(major: 1, minor: 0, patch: 0),
            defaults: makeDefaults()
        )
        model.automaticChecksEnabled = false

        await model.refresh(force: false, at: Date(timeIntervalSince1970: 1_000))
        #expect(await provider.requestCount == 0)

        await model.refresh(force: true, at: Date(timeIntervalSince1970: 1_000))
        #expect(await provider.requestCount == 1)
        #expect(model.state == .upToDate)
    }

    @Test
    func providerFailureIsReported() async {
        let model = UpdateFeatureModel(
            provider: ReleaseProviderFake(release: nil),
            currentVersion: AppVersion(major: 1, minor: 0, patch: 0),
            defaults: makeDefaults()
        )

        await model.refresh(force: true, at: Date(timeIntervalSince1970: 1_000))

        #expect(model.state == .failed)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "UpdateFeatureModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private actor ReleaseProviderFake: AppReleaseProviding {
    private enum FakeError: Error {
        case unavailable
    }

    let release: AppRelease?
    private(set) var requestCount = 0

    init(release: AppRelease?) {
        self.release = release
    }

    func latestRelease() async throws -> AppRelease {
        requestCount += 1
        guard let release else {
            throw FakeError.unavailable
        }
        return release
    }
}
