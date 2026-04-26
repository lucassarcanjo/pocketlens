import Foundation

/// Pluggable transport for the Mistral OCR client. The default talks to
/// `URLSession.shared`; tests inject a stub.
public protocol MistralTransport: Sendable {
    func send(request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct MistralURLSessionTransport: MistralTransport {
    private let session: URLSession

    public init(timeoutInterval: TimeInterval = 300) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = timeoutInterval
        config.timeoutIntervalForResource = max(timeoutInterval * 2, 600)
        self.session = URLSession(configuration: config)
    }

    public func send(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MistralOCRError.network(statusCode: 0, body: "non-HTTP response")
        }
        return (data, http)
    }
}

public enum MistralOCRError: Error, Sendable {
    case missingAPIKey
    case network(statusCode: Int, body: String)
    case decoding(String)
}

extension MistralOCRError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Mistral API key is missing. Add one in Settings."
        case .network(let status, let body):
            let snippet = body.prefix(400)
            return "Mistral OCR HTTP \(status): \(snippet)"
        case .decoding(let detail):
            return "Mistral OCR response couldn't be decoded: \(detail)"
        }
    }
}

/// Mistral OCR client. POSTs a base64-encoded PDF to `/v1/ocr` and returns
/// markdown per page. PDFKit's text recovery was unreliable on Itaú statements
/// (column ordering and glyph drops), so we hand the bytes off to Mistral and
/// feed the cleaner markdown into the Claude extraction step.
///
/// Privacy note: the **un-redacted** PDF crosses the wire to Mistral; the
/// `Redactor` only runs on the OCR markdown before it reaches Anthropic.
/// The disclosure copy in the UI must reflect that.
public struct MistralOCRClient: Sendable {

    public let apiKey: String
    public let model: String
    public let transport: any MistralTransport
    public let endpoint: URL
    public let maxRetries: Int
    public let requestTimeout: TimeInterval

    public init(
        apiKey: String,
        model: String = "mistral-ocr-latest",
        transport: any MistralTransport = MistralURLSessionTransport(),
        endpoint: URL = URL(string: "https://api.mistral.ai/v1/ocr")!,
        maxRetries: Int = 3,
        requestTimeout: TimeInterval = 300
    ) {
        self.apiKey = apiKey
        self.model = model
        self.transport = transport
        self.endpoint = endpoint
        self.maxRetries = maxRetries
        self.requestTimeout = requestTimeout
    }

    public struct Output: Sendable {
        public let pages: [String]
        public let combined: String

        public var pageCount: Int { pages.count }

        public init(pages: [String]) {
            self.pages = pages
            self.combined = pages.enumerated().map { idx, text in
                "<<<PAGE \(idx + 1)>>>\n\(text)"
            }.joined(separator: "\n\n")
        }
    }

    public func extract(data: Data) async throws -> Output {
        guard !apiKey.isEmpty else { throw MistralOCRError.missingAPIKey }

        let base64 = data.base64EncodedString()
        let payload: [String: Any] = [
            "model": model,
            "document": [
                "type": "document_url",
                "document_url": "data:application/pdf;base64,\(base64)",
            ],
            "include_image_base64": false,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: endpoint, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (responseData, http) = try await sendWithRetries(request)
        guard (200..<300).contains(http.statusCode) else {
            throw MistralOCRError.network(
                statusCode: http.statusCode,
                body: String(data: responseData, encoding: .utf8) ?? ""
            )
        }

        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: responseData)
        } catch {
            throw MistralOCRError.decoding("MistralOCRClient response: \(error)")
        }

        let sortedPages = decoded.pages.sorted(by: { $0.index < $1.index })
        return Output(pages: sortedPages.map(\.markdown))
    }

    public func extract(url: URL) async throws -> Output {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try await extract(data: data)
    }

    // MARK: - Response shape

    struct Response: Decodable {
        let pages: [Page]
        struct Page: Decodable {
            let index: Int
            let markdown: String
        }
    }

    // MARK: - Retry

    func sendWithRetries(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        var lastError: Error?
        while attempt < maxRetries {
            attempt += 1
            do {
                let (data, http) = try await transport.send(request: request)
                if http.statusCode == 429 || (500..<600).contains(http.statusCode) {
                    if attempt < maxRetries {
                        try await Task.sleep(nanoseconds: backoffNanos(attempt: attempt))
                        continue
                    }
                }
                return (data, http)
            } catch {
                lastError = error
                if attempt >= maxRetries { break }
                try await Task.sleep(nanoseconds: backoffNanos(attempt: attempt))
            }
        }
        if let lastError { throw lastError }
        throw MistralOCRError.network(statusCode: 0, body: "no transport response")
    }

    /// Exponential backoff: 250ms, 500ms, 1s, 2s, ... bounded at 8s.
    func backoffNanos(attempt: Int) -> UInt64 {
        let base: Double = 0.25
        let capped = min(base * pow(2.0, Double(attempt - 1)), 8.0)
        return UInt64(capped * 1_000_000_000)
    }
}
