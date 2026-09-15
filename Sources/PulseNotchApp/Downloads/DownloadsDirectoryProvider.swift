import Foundation
import PulseNotchCore

actor DownloadsDirectoryProvider: DownloadsProviding {
    private static let partialExtensions: Set<String> = ["crdownload", "download", "opdownload", "part"]

    func activeDownloads(in directory: URL) throws -> [DetectedDownload] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileAllocatedSizeKey, .fileSizeKey]
        )

        return urls.compactMap { url in
            guard Self.partialExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            return DetectedDownload(id: url.path, byteCount: Self.byteCount(at: url))
        }
    }

    private static func byteCount(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileAllocatedSizeKey, .fileSizeKey]

        func size(of item: URL) -> Int64 {
            let values = try? item.resourceValues(forKeys: keys)
            guard values?.isDirectory != true else { return 0 }
            return Int64(values?.fileAllocatedSize ?? values?.fileSize ?? 0)
        }

        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
            return size(of: url)
        }

        guard let children = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys)
        ) else { return 0 }

        return children.reduce(into: Int64(0)) { total, child in
            guard let child = child as? URL else { return }
            total += size(of: child)
        }
    }
}
