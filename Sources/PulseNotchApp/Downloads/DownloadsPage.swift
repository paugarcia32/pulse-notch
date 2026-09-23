import PulseNotchCore
import SwiftUI

struct DownloadsPage: View {
    @ObservedObject var model: DownloadFeatureModel
    let testingDownloads: [DetectedDownload]?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    init(model: DownloadFeatureModel, testingDownloads: [DetectedDownload]? = nil) {
        self.model = model
        self.testingDownloads = testingDownloads
    }

    var body: some View {
        let downloads = testingDownloads ?? model.activeDownloads
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("DOWNLOADS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text(downloads.isEmpty ? "Idle" : "\(downloads.count) active")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 16)

            if downloads.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 7) {
                        ForEach(downloads) { download in
                            downloadCard(download)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var tileFill: Color { .white.opacity(contrast == .increased ? 0.14 : 0.08) }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No active downloads").font(.callout.weight(.semibold))
            Text("New downloads will appear here")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func downloadCard(_ download: DetectedDownload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                activityIcon(for: download)
                    .frame(width: 30, height: 30)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(download.fileName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(download.source == .homebrew ? "Homebrew activity" : download.directoryURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if let percentage = download.percentage {
                    Text("\(percentage)%")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .fixedSize()
                } else {
                    Text("Active")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let progress = download.progress {
                ProgressView(value: progress)
                    .tint(.blue)
                    .scaleEffect(x: 1, y: 0.7, anchor: .center)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: download))
    }

    @ViewBuilder
    private func activityIcon(for download: DetectedDownload) -> some View {
        if download.source == .homebrew {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
        } else {
            DownloadActivityIndicator(color: .blue, reduceMotion: reduceMotion)
        }
    }

    static func accessibilityLabel(for download: DetectedDownload) -> String {
        if download.source == .homebrew {
            return "\(download.fileName), Homebrew activity in progress"
        }
        let progress = download.percentage.map { ", \($0) percent complete" } ?? ", progress unavailable"
        return "Downloading \(download.fileName)\(progress), to \(download.directoryURL.path)"
    }
}
