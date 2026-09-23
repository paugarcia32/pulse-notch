import Foundation
import Testing
@testable import PulseNotchApp

struct HomebrewUpdaterTests {
    @Test
    func caskMustHaveTheNewReleaseAndAnOlderInstallation() {
        func info(_ available: String, _ installed: String) -> Data {
            Data("""
            {"casks":[{"version":"\(available)","installed":"\(installed)"}]}
            """.utf8)
        }
        let release = AppVersion(major: 1, minor: 2, patch: 0)
        #expect(HomebrewCaskInfo.canUpgrade(info("1.2.0", "1.1.0"), to: release))
        #expect(!HomebrewCaskInfo.canUpgrade(info("1.1.0", "1.0.0"), to: release))
        #expect(!HomebrewCaskInfo.canUpgrade(info("1.2.0", "1.2.0"), to: release))
        #expect(!HomebrewCaskInfo.canUpgrade(Data("{}".utf8), to: release))
    }

    @Test
    func onlyTheUnmodifiedHomebrewAppAtItsConfiguredDestinationIsOwned() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = root.appendingPathComponent("homebrew")
        let metadata = prefix.appendingPathComponent("Caskroom/pulse-notch/.metadata")
        let staged = prefix.appendingPathComponent("Caskroom/pulse-notch/1.0.0/Pulse Notch.app")
        let installed = root.appendingPathComponent("Applications/Pulse Notch.app")
        let binary = "Contents/MacOS/PulseNotch"
        for directory in [metadata, staged.appendingPathComponent("Contents/MacOS"),
                          installed.appendingPathComponent("Contents/MacOS")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("original".utf8).write(to: staged.appendingPathComponent(binary))
        try Data("original".utf8).write(to: installed.appendingPathComponent(binary))
        try Data(#"{"source":{"tap":"paugarcia32/tap"}}"#.utf8)
            .write(to: metadata.appendingPathComponent("INSTALL_RECEIPT.json"))
        let configuration = """
        {"default":{"appdir":"\(root.appendingPathComponent("Applications").path)"},"explicit":{}}
        """
        try Data(configuration.utf8).write(to: metadata.appendingPathComponent("config.json"))
        let listing = staged.path + "\n"

        #expect(HomebrewCaskInfo.ownsRunningApp(listing, at: installed, prefix: prefix))
        #expect(!HomebrewCaskInfo.ownsRunningApp(listing, at: staged, prefix: prefix))
        try Data("replaced".utf8).write(to: installed.appendingPathComponent(binary))
        #expect(!HomebrewCaskInfo.ownsRunningApp(listing, at: installed, prefix: prefix))
    }
}
