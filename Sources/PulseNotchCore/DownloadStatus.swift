import Foundation

public struct DetectedDownload: Identifiable, Equatable, Sendable {
    public let id: String
    public let byteCount: Int64

    public init(id: String, byteCount: Int64) {
        self.id = id
        self.byteCount = max(byteCount, 0)
    }
}

public protocol DownloadsProviding: Sendable {
    func activeDownloads(in directory: URL) async throws -> [DetectedDownload]
}
