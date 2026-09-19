import Combine
import Foundation
import PulseNotchCore

@MainActor
final class DownloadFeatureModel: ObservableObject {
    @Published private(set) var activeDownloads: [DetectedDownload] = []

    private let provider: any DownloadsProviding
    private var directory: URL?
    private var includeHomebrew = false
    private var initialByteCounts: [String: Int64] = [:]

    init(provider: any DownloadsProviding) {
        self.provider = provider
    }

    func startMonitoring(directory: URL, includeHomebrew: Bool = false) async {
        stopMonitoring()
        self.directory = directory
        self.includeHomebrew = includeHomebrew

        if let initial = try? await provider.activeDownloads(in: directory, includeHomebrew: includeHomebrew) {
            initialByteCounts = Dictionary(uniqueKeysWithValues: initial.compactMap { download in
                download.source == .file ? (download.id, download.byteCount) : nil
            })
        }
    }

    func stopMonitoring() {
        directory = nil
        includeHomebrew = false
        initialByteCounts.removeAll()
        activeDownloads.removeAll()
    }

    func refresh() async {
        guard let directory,
              let downloads = try? await provider.activeDownloads(in: directory, includeHomebrew: includeHomebrew)
        else { return }

        let activeIDs = Set(downloads.map(\.id))
        initialByteCounts = initialByteCounts.filter { activeIDs.contains($0.key) }
        activeDownloads = downloads.filter { download in
            guard download.source == .file else { return true }
            guard let initialByteCount = initialByteCounts[download.id] else { return true }
            return download.byteCount > initialByteCount
        }
    }
}
