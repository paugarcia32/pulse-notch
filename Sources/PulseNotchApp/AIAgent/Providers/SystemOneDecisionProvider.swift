import Foundation
import PulseNotchCore

/// A decision provider reached over HTTP through the System One API: TypeSafe's
/// hosted JEV, or an existing Laya-compatible service.
struct SystemOneDecisionProvider: DecisionProvider {
    static let typeSafeBaseURL = URL(string: "https://api.typesafe.ai")!
    /// JEV accepts 32k tokens for the state plus the longest question.
    static let jevContextLimit = 32_000
    /// The multilingual Laya checkpoint's encoder context.
    static let layaContextLimit = 1_024

    let baseURL: URL
    let model: String
    let apiKey: String?
    let contextLimit: Int
    let metadata: DecisionProviderMetadata
    let requestTimeout: TimeInterval
    let maximumRetries: Int
    private let session: URLSession
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        baseURL: URL,
        model: String,
        apiKey: String?,
        providerName: String,
        contextLimit: Int,
        session: URLSession = .shared,
        requestTimeout: TimeInterval = 10,
        maximumRetries: Int = 2,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.contextLimit = contextLimit
        self.metadata = DecisionProviderMetadata(provider: providerName, model: model, isLocal: baseURL.isLoopback)
        self.session = session
        self.requestTimeout = requestTimeout
        self.maximumRetries = maximumRetries
        self.sleep = sleep
    }

    static func jev(model: String, apiKey: String, session: URLSession = .shared) -> SystemOneDecisionProvider {
        SystemOneDecisionProvider(
            baseURL: typeSafeBaseURL,
            model: model,
            apiKey: apiKey,
            providerName: "JEV",
            contextLimit: jevContextLimit,
            session: session
        )
    }

    static func layaEndpoint(url: URL, model: String, apiKey: String?, session: URLSession = .shared) -> SystemOneDecisionProvider {
        SystemOneDecisionProvider(
            baseURL: url,
            model: model,
            apiKey: apiKey,
            providerName: "Laya",
            contextLimit: layaContextLimit,
            session: session,
            requestTimeout: 30
        )
    }

    func decide(_ request: DecisionRequest) async throws -> DecisionResponse {
        var urlRequest = URLRequest(url: baseURL.appending(path: "v1/systemone"), timeoutInterval: requestTimeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try SystemOneWire.encode(request, model: model)

        var attempt = 0
        while true {
            try Task.checkCancellation()
            let (data, response) = try await send(urlRequest)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200..<300:
                let object: Any
                do {
                    object = try JSONSerialization.jsonObject(with: data)
                } catch {
                    throw DecisionProviderError.malformedResponse("The response is not JSON.")
                }
                let decoded = try SystemOneWire.decodeAnswers(object, for: request)
                return DecisionResponse(
                    answers: decoded.answers,
                    metadata: DecisionProviderMetadata(
                        provider: metadata.provider,
                        model: decoded.model ?? model,
                        isLocal: metadata.isLocal,
                        inputTokens: decoded.inputTokens
                    )
                )
            case 401, 403:
                throw DecisionProviderError.unauthorized
            case 429, 529, 503:
                let retryAfter = (response as? HTTPURLResponse)?
                    .value(forHTTPHeaderField: "retry-after")
                    .flatMap(TimeInterval.init)
                guard attempt < maximumRetries else {
                    throw DecisionProviderError.rateLimited(retryAfter: retryAfter)
                }
                attempt += 1
                let delay = min(retryAfter ?? pow(2, Double(attempt - 1)), 10)
                try await sleep(.milliseconds(Int(delay * 1_000)))
            case 422:
                throw DecisionProviderError.malformedResponse(Self.errorDetail(from: data) ?? "The request was rejected as invalid.")
            default:
                throw DecisionProviderError.unavailable(Self.errorDetail(from: data) ?? "HTTP \(status)")
            }
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .timedOut: throw DecisionProviderError.timedOut
            default: throw DecisionProviderError.unavailable(error.localizedDescription)
            }
        }
    }

    static func errorDetail(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let message = object["error"] as? String { return message }
        if let detail = object["detail"] as? String { return detail }
        return nil
    }
}
