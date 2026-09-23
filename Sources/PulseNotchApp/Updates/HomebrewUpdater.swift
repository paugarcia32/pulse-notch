import AppKit
import CryptoKit
import Foundation

struct HomebrewCaskInfo: Decodable {
    struct Cask: Decodable {
        let version: String
        let installed: String?
    }

    let casks: [Cask]

    static func canUpgrade(_ data: Data, to version: AppVersion) -> Bool {
        guard let cask = try? JSONDecoder().decode(Self.self, from: data).casks.first,
              let available = AppVersion(cask.version), available >= version,
              let installed = cask.installed, let installedVersion = AppVersion(installed),
              installedVersion < version else {
            return false
        }
        return true
    }

    private struct Receipt: Decodable {
        struct Source: Decodable { let tap: String }
        let source: Source
    }

    private struct Configuration: Decodable {
        struct Paths: Decodable { let appdir: String? }
        let `default`: Paths
        let explicit: Paths?
    }

    static func ownsRunningApp(_ listing: String, at appURL: URL, prefix: URL) -> Bool {
        let caskroom = prefix.appendingPathComponent("Caskroom/pulse-notch")
        let metadata = caskroom.appendingPathComponent(".metadata")
        guard let receipt = try? JSONDecoder().decode(
            Receipt.self, from: Data(contentsOf: metadata.appendingPathComponent("INSTALL_RECEIPT.json"))
        ), receipt.source.tap == "paugarcia32/tap",
              let configuration = try? JSONDecoder().decode(
                Configuration.self, from: Data(contentsOf: metadata.appendingPathComponent("config.json"))
              ),
              let staged = listing.split(whereSeparator: \.isNewline).map(String.init).first(where: {
                  $0.hasPrefix(caskroom.path + "/") && $0.hasSuffix("/Pulse Notch.app")
              }) else { return false }

        guard let appdir = configuration.explicit?.appdir ?? configuration.default.appdir else { return false }
        let destination = URL(fileURLWithPath: appdir).appendingPathComponent("Pulse Notch.app")
        guard destination.standardizedFileURL.resolvingSymlinksInPath() ==
                appURL.standardizedFileURL.resolvingSymlinksInPath() else { return false }

        let binary = "Contents/MacOS/PulseNotch"
        guard let installed = try? Data(contentsOf: appURL.appendingPathComponent(binary)),
              let original = try? Data(contentsOf: URL(fileURLWithPath: staged).appendingPathComponent(binary)) else {
            return false
        }
        return SHA256.hash(data: installed) == SHA256.hash(data: original)
    }
}

actor HomebrewUpdater {
    enum Preparation {
        case ready(URL)
        case unavailable
    }

    func prepare(appURL: URL, version: AppVersion) -> Preparation {
        guard let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .map({ URL(fileURLWithPath: $0) })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            return .unavailable
        }

        guard let listing = try? run(brew, ["list", "--cask", "--verbose", "pulse-notch"]) else {
            return .unavailable
        }
        guard HomebrewCaskInfo.ownsRunningApp(
            listing, at: appURL, prefix: brew.deletingLastPathComponent().deletingLastPathComponent()
        ) else { return .unavailable }
        guard let info = try? run(brew, ["info", "--cask", "--json=v2", "pulse-notch"]) else {
            return .unavailable
        }
        guard HomebrewCaskInfo.canUpgrade(Data(info.utf8), to: version) else { return .unavailable }
        return .ready(brew)
    }

    private func run(_ executable: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
        return String(decoding: data, as: UTF8.self)
    }
}

@MainActor
final class HomebrewUpdateCoordinator: ObservableObject {
    @Published private(set) var isPreparing = false
    @Published private(set) var errorMessage: String?

    private let updater = HomebrewUpdater()
    private let resultURL: URL?

    init() {
        resultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("PulseNotch/homebrew-update-result")
        if let resultURL, (try? String(contentsOf: resultURL, encoding: .utf8)) == "failed" {
            errorMessage = "Homebrew couldn't update Pulse Notch. Check Homebrew in Terminal and try again."
        }
        if let resultURL { try? FileManager.default.removeItem(at: resultURL) }
    }

    func install(_ release: AppRelease) {
        guard !isPreparing else { return }
        isPreparing = true
        errorMessage = nil
        Task {
            defer { isPreparing = false }
            guard let resultURL else {
                NSWorkspace.shared.open(release.pageURL)
                return
            }
            let appURL = Bundle.main.bundleURL
            do {
                switch await updater.prepare(appURL: appURL, version: release.version) {
                case .unavailable:
                    NSWorkspace.shared.open(release.pageURL)
                case let .ready(brew):
                    let helper = appURL.appendingPathComponent("Contents/MacOS/PulseNotchUpdater")
                    guard FileManager.default.isExecutableFile(atPath: helper.path) else {
                        NSWorkspace.shared.open(release.pageURL)
                        return
                    }
                    try FileManager.default.createDirectory(
                        at: resultURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    let process = Process()
                    process.executableURL = helper
                    process.arguments = [String(ProcessInfo.processInfo.processIdentifier), brew.path, appURL.path, resultURL.path]
                    try process.run()
                    NSApp.terminate(nil)
                }
            } catch {
                errorMessage = "Could not start the Homebrew update. You can update from the release page."
            }
        }
    }
}
