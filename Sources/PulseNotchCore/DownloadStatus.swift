import Foundation

public enum DownloadSource: Equatable, Sendable {
    case file
    case homebrew
}

public struct DetectedDownload: Identifiable, Equatable, Sendable {
    public let id: String
    public let fileName: String
    public let directoryURL: URL
    public let byteCount: Int64
    public let totalByteCount: Int64?
    public let source: DownloadSource

    public init(
        id: String,
        fileName: String? = nil,
        directoryURL: URL? = nil,
        byteCount: Int64,
        totalByteCount: Int64? = nil,
        source: DownloadSource = .file
    ) {
        self.id = id
        self.fileName = fileName ?? URL(fileURLWithPath: id).deletingPathExtension().lastPathComponent
        self.directoryURL = directoryURL ?? URL(fileURLWithPath: id).deletingLastPathComponent()
        self.byteCount = max(byteCount, 0)
        self.totalByteCount = totalByteCount.map { max($0, 0) }
        self.source = source
    }

    public var progress: Double? {
        guard let totalByteCount, totalByteCount > 0 else { return nil }
        return min(Double(byteCount) / Double(totalByteCount), 1)
    }

    public var percentage: Int? { progress.map { Int(($0 * 100).rounded(.down)) } }
}

public protocol DownloadsProviding: Sendable {
    func activeDownloads(in directory: URL, includeHomebrew: Bool) async throws -> [DetectedDownload]
}
