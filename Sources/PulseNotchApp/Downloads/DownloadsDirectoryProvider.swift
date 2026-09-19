import Foundation
import PulseNotchCore

actor DownloadsDirectoryProvider: DownloadsProviding {
    private static let partialExtensions: Set<String> = ["crdownload", "download", "opdownload", "part"]
    private static let homebrewOperations: [String: String] = [
        "fetch": "Fetching Homebrew packages",
        "install": "Installing with Homebrew",
        "reinstall": "Reinstalling with Homebrew",
        "update": "Updating Homebrew",
        "upgrade": "Upgrading Homebrew packages"
    ]

    func activeDownloads(in directory: URL, includeHomebrew: Bool) throws -> [DetectedDownload] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileAllocatedSizeKey, .fileSizeKey]
        )

        let fileDownloads: [DetectedDownload] = urls.compactMap { url in
            guard Self.partialExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            return Self.download(at: url)
        }
        guard includeHomebrew else { return fileDownloads }

        let processList = try? CommandOutput.read(
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,command="]
        )
        return fileDownloads + Self.homebrewDownloads(from: processList ?? "")
    }

    static func download(at url: URL) -> DetectedDownload {
        let safariProgress = safariProgress(at: url)
        return DetectedDownload(
            id: url.path,
            fileName: url.deletingPathExtension().lastPathComponent,
            directoryURL: url.deletingLastPathComponent(),
            byteCount: safariProgress?.completed ?? byteCount(at: url),
            totalByteCount: safariProgress?.total
        )
    }

    static func homebrewDownloads(from processList: String) -> [DetectedDownload] {
        var foundOperations: Set<String> = []

        return processList.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 1, whereSeparator: \Character.isWhitespace)
            guard fields.count == 2 else { return nil }

            let arguments = fields[1].split(whereSeparator: \Character.isWhitespace).map(String.init)
            guard let brewIndex = arguments.firstIndex(where: isHomebrewExecutable),
                  let operation = arguments[arguments.index(after: brewIndex)...]
                    .first(where: { homebrewOperations[$0] != nil }),
                  foundOperations.insert(operation).inserted,
                  let title = homebrewOperations[operation]
            else { return nil }

            return DetectedDownload(
                id: "homebrew-\(operation)",
                fileName: title,
                directoryURL: URL(fileURLWithPath: "/", isDirectory: true),
                byteCount: 0,
                source: .homebrew
            )
        }
    }

    private static func isHomebrewExecutable(_ argument: String) -> Bool {
        let name = URL(fileURLWithPath: argument).lastPathComponent
        return name == "brew" || name == "brew.rb" || name == "brew.sh"
    }

    private static func safariProgress(at url: URL) -> (completed: Int64, total: Int64)? {
        guard url.pathExtension.lowercased() == "download",
              let data = try? Data(contentsOf: url.appendingPathComponent("Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = plist as? [String: Any],
              let completed = (values["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value,
              let total = (values["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value,
              total > 0
        else { return nil }
        return (max(completed, 0), total)
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
