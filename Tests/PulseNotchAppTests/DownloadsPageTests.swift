import Foundation
import PulseNotchCore
import Testing
@testable import PulseNotchApp

@MainActor
struct DownloadsPageTests {
    @Test
    func knownProgressAnnouncesPercentageAndFullDestination() {
        let download = DetectedDownload(
            id: "/Users/example/Downloads/archive.zip.part",
            fileName: "archive.zip",
            directoryURL: URL(fileURLWithPath: "/Users/example/Downloads", isDirectory: true),
            byteCount: 42,
            totalByteCount: 100
        )

        #expect(DownloadsPage.accessibilityLabel(for: download) ==
            "Downloading archive.zip, 42 percent complete, to /Users/example/Downloads")
    }

    @Test
    func unknownProgressAndHomebrewNeverClaimAPercentage() {
        let file = DetectedDownload(id: "/tmp/sample.zip.part", byteCount: 5)
        let homebrew = DetectedDownload(
            id: "homebrew-install", fileName: "Installing with Homebrew",
            byteCount: 0, source: .homebrew
        )

        #expect(DownloadsPage.accessibilityLabel(for: file) ==
            "Downloading sample.zip, progress unavailable, to /tmp")
        #expect(DownloadsPage.accessibilityLabel(for: homebrew) ==
            "Installing with Homebrew, Homebrew activity in progress")
    }

    @Test
    func downloadPreviewUsesAReadableFileName() throws {
        let preview = try #require(CollapsedIndicatorPreview.download.testingDownload(instance: 0))

        #expect(preview.fileName == "Sample download 1.zip")
        #expect(preview.percentage == 42)
    }
}
