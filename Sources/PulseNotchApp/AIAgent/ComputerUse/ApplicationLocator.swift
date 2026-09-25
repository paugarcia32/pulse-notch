import Foundation

/// Finds application bundles by name in the standard application folders.
struct ApplicationLocator {
    let searchDirectories: [URL]
    let fileExists: (URL) -> Bool
    let directoryContents: (URL) -> [String]

    static func standard() -> ApplicationLocator {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ApplicationLocator(
            searchDirectories: [
                URL(filePath: "/Applications", directoryHint: .isDirectory),
                URL(filePath: "/System/Applications", directoryHint: .isDirectory),
                URL(filePath: "/System/Applications/Utilities", directoryHint: .isDirectory),
                home.appending(path: "Applications", directoryHint: .isDirectory)
            ],
            fileExists: { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) },
            directoryContents: { directory in
                (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
            }
        )
    }

    /// Bundles named `<name>.app`, in search-directory order, matched case-insensitively.
    func candidates(forApplicationNamed name: String) -> [URL] {
        guard let bundleName = Self.bundleFileName(for: name) else { return [] }
        return searchDirectories.compactMap { directory in
            let exact = directory.appending(path: bundleName, directoryHint: .isDirectory)
            if fileExists(exact) { return exact }
            let match = directoryContents(directory).first { $0.caseInsensitiveCompare(bundleName) == .orderedSame }
            return match.map { directory.appending(path: $0, directoryHint: .isDirectory) }
        }
    }

    /// Reverse-DNS names such as `com.apple.Safari`.
    static func looksLikeBundleIdentifier(_ name: String) -> Bool {
        let components = name.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2, !name.lowercased().hasSuffix(".app") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        return components.allSatisfy { component in
            !component.isEmpty && component.unicodeScalars.allSatisfy(allowed.contains)
        }
    }

    /// Rejects names that could escape the search directories.
    private static func bundleFileName(for name: String) -> String? {
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasSuffix(".app") { trimmed = String(trimmed.dropLast(4)) }
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.hasPrefix(".") else { return nil }
        return trimmed + ".app"
    }
}
