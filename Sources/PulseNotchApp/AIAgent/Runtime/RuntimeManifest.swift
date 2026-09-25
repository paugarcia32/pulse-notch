import Foundation

/// Pinned versions, sources, checksums, and licenses for optional local components.
/// Nothing in it is downloaded until the user selects Install.
struct RuntimeManifest: Codable, Hashable, Sendable {
    struct Archive: Codable, Hashable, Sendable {
        let url: URL
        let size: Int64
        let sha256: String
    }

    struct Packages: Codable, Hashable, Sendable {
        let lockFile: String
        let requirement: String
        let estimatedSize: Int64
    }

    struct Runtime: Codable, Hashable, Sendable, Identifiable {
        let id: String
        let name: String
        let version: String
        let license: String
        let source: URL
        let minimumMacOS: String
        let architectures: [String]
        let archive: Archive
        let packages: Packages?
        let executable: String?

        var installedSize: Int64 { archive.size * 3 + (packages?.estimatedSize ?? 0) }
    }

    struct ModelFile: Codable, Hashable, Sendable {
        enum Role: String, Codable, Sendable {
            case model
            case visionProjector
        }

        let path: String
        let role: Role?
        let size: Int64
        let sha256: String?
        /// Hugging Face stores small files in Git; their identity is the Git blob hash.
        let gitBlobSHA1: String?
    }

    struct Model: Codable, Hashable, Sendable, Identifiable {
        let id: String
        let name: String
        let repository: String
        let revision: String
        let license: String
        let runtime: String
        let files: [ModelFile]
        let upstream: String?
        let contextLimit: Int?
        let contextLength: Int?
        let minimumMemoryGB: Int?
        let notes: String?

        var downloadSize: Int64 { files.reduce(0) { $0 + $1.size } }

        func url(for file: ModelFile) -> URL? {
            let encodedPath = file.path.split(separator: "/").map {
                String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
            }.joined(separator: "/")
            return URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(encodedPath)")
        }
    }

    let manifestVersion: Int
    let runtimes: [Runtime]
    let decisionModels: [Model]
    let languageModels: [Model]

    func runtime(_ id: String) -> Runtime? { runtimes.first { $0.id == id } }
    func model(_ id: String) -> Model? { (decisionModels + languageModels).first { $0.id == id } }

    static func bundled(bundle: Bundle = .module) throws -> RuntimeManifest {
        guard let url = bundle.url(forResource: "RuntimeManifest", withExtension: "json") else {
            throw RuntimeError.manifestMissing
        }
        return try JSONDecoder().decode(RuntimeManifest.self, from: Data(contentsOf: url))
    }
}

enum RuntimeError: Error, Hashable, Sendable {
    case manifestMissing
    case unsupportedSystem(String)
    case insufficientDiskSpace(required: Int64, available: Int64)
    case downloadFailed(String)
    case checksumMismatch(String)
    case installationFailed(String)
    case notInstalled(String)
    case launchFailed(String)
    case invalidModelFile(String)

    var userMessage: String {
        switch self {
        case .manifestMissing: "The runtime manifest is missing from the app bundle."
        case .unsupportedSystem(let detail): detail
        case .insufficientDiskSpace(let required, let available):
            "Not enough disk space: \(Self.bytes(required)) needed, \(Self.bytes(available)) available."
        case .downloadFailed(let detail): "The download failed: \(detail)"
        case .checksumMismatch(let file): "The checksum of \(file) does not match the manifest. The file was removed."
        case .installationFailed(let detail): "Installation failed: \(detail)"
        case .notInstalled(let name): "\(name) is not installed."
        case .launchFailed(let detail): "The local runtime could not start: \(detail)"
        case .invalidModelFile(let detail): "The model file is not compatible: \(detail)"
        }
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
