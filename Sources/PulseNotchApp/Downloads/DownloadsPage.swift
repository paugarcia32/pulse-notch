import PulseNotchCore
import SwiftUI

struct DownloadsPage: View {
    @ObservedObject var model: DownloadFeatureModel
    let testingDownloads: [DetectedDownload]?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: DownloadFeatureModel, testingDownloads: [DetectedDownload]? = nil) {
        self.model = model
        self.testingDownloads = testingDownloads
    }

    var body: some View {
        let downloads = testingDownloads ?? model.activeDownloads
        ZStack(alignment: .topLeading) {
            if downloads.isEmpty {
                ContentUnavailableView(
                    "No active downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("New downloads will appear here")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("Downloads", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)

                if !downloads.isEmpty {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(downloads) { download in
                                downloadCard(download)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func downloadCard(_ download: DetectedDownload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(download.fileName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Text(download.percentage.map { "\($0)%" } ?? "—")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.blue)
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }

            if let progress = download.progress {
                ProgressView(value: progress)
                    .tint(.blue)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            Label(
                download.source == .homebrew ? "Homebrew activity" : download.directoryURL.path,
                systemImage: download.source == .homebrew ? "shippingbox" : "folder"
            )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: download))
    }

    private func accessibilityLabel(for download: DetectedDownload) -> String {
        if download.source == .homebrew {
            return "\(download.fileName) in progress"
        }
        let progress = download.percentage.map { ", \($0) percent" } ?? ", progress unavailable"
        return "Downloading \(download.fileName)\(progress), to \(download.directoryURL.path)"
    }
}
