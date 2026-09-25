import CryptoKit
import Foundation

protocol FileDownloading: Sendable {
    /// Downloads `url` to `destination`, resuming from a partial file left by an
    /// earlier attempt. Cancelling the calling task cancels the transfer.
    func download(
        _ url: URL,
        to destination: URL,
        expectedSize: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws
}

/// Streams large downloads straight to disk and resumes them with HTTP ranges.
struct URLSessionFileDownloader: FileDownloading {
    func download(
        _ url: URL,
        to destination: URL,
        expectedSize: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
        if existing > 0, existing == expectedSize { return }
        if existing > expectedSize { try? FileManager.default.removeItem(at: destination) }
        let offset = existing > expectedSize ? 0 : existing

        let transfer = try RangedTransfer(destination: destination, offset: offset, progress: progress)
        try await transfer.run(url: url)
    }
}

private final class RangedTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    // Delegate callbacks arrive on the session's serial delegate queue; the lock
    // guards state shared with the cancellation handler.
    private let lock = NSLock()
    private let handle: FileHandle
    private let progress: @Sendable (Int64) -> Void
    private var received: Int64
    private let offset: Int64
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDataTask?
    private var failure: Error?

    init(destination: URL, offset: Int64, progress: @escaping @Sendable (Int64) -> Void) throws {
        if !FileManager.default.fileExists(atPath: destination.path) {
            FileManager.default.createFile(atPath: destination.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: destination)
        try handle.truncate(atOffset: UInt64(offset))
        try handle.seekToEnd()
        self.offset = offset
        self.received = offset
        self.progress = progress
    }

    func run(url: URL) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                self.continuation = continuation
                let task = session.dataTask(with: request)
                self.task = task
                lock.unlock()
                if Task.isCancelled { task.cancel() } else { task.resume() }
            }
        } onCancel: {
            lock.lock()
            let task = self.task
            lock.unlock()
            task?.cancel()
        }
        try? handle.close()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if offset > 0 && status == 200 {
            // The server ignored the range; start over.
            try? handle.truncate(atOffset: 0)
            lock.lock()
            received = 0
            lock.unlock()
        } else if !(200..<300).contains(status) {
            lock.lock()
            failure = RuntimeError.downloadFailed("HTTP \(status)")
            lock.unlock()
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try handle.write(contentsOf: data)
        } catch {
            lock.lock()
            failure = RuntimeError.downloadFailed(error.localizedDescription)
            lock.unlock()
            dataTask.cancel()
            return
        }
        lock.lock()
        received += Int64(data.count)
        let total = received
        lock.unlock()
        progress(total)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let failure = self.failure
        lock.unlock()
        if let failure {
            continuation?.resume(throwing: failure)
        } else if let error = error as? URLError, error.code == .cancelled {
            continuation?.resume(throwing: CancellationError())
        } else if let error {
            continuation?.resume(throwing: RuntimeError.downloadFailed(error.localizedDescription))
        } else {
            continuation?.resume()
        }
    }
}

enum FileDigest {
    static func sha256(of url: URL) throws -> String {
        var hasher = SHA256()
        try stream(url) { hasher.update(data: $0) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The identifier Git (and Hugging Face) use for small files.
    static func gitBlobSHA1(of url: URL) throws -> String {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(size)\0".utf8))
        try stream(url) { hasher.update(data: $0) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func stream(_ url: URL, _ body: (Data) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 8 * 1024 * 1024), !chunk.isEmpty {
            body(chunk)
        }
    }
}
