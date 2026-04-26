import Foundation
import Domain

/// Pluggable transport — abstracted so unit tests can hand back canned
/// responses without making real network calls. The default implementation
/// is `URLSession.shared`.
public protocol AnthropicTransport: Sendable {
    func send(request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: AnthropicTransport {
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
            throw LLMError.network(statusCode: 0, body: "non-HTTP response")
        }
        return (data, http)
    }
}

/// Anthropic Messages API client. Tool-use mode with strict schema, prompt
/// caching on the system prompt, no streaming, retries on 429/5xx.
public struct AnthropicProvider: LLMProvider {
    public let kind: LLMProviderKind = .anthropic
    public let model: String

    public let apiKey: String
    public let transport: any AnthropicTransport
    public let endpoint: URL
    public let apiVersion: String
    public let maxTokens: Int
    public let maxRetries: Int
    public let requestTimeout: TimeInterval

    public init(
        apiKey: String,
        model: String = "claude-sonnet-4-6",
        transport: any AnthropicTransport = URLSessionTransport(),
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        apiVersion: String = "2023-06-01",
        maxTokens: Int = 64_000,
        maxRetries: Int = 3,
        requestTimeout: TimeInterval = 300
    ) {
        self.apiKey = apiKey
        self.model = model
        self.transport = transport
        self.endpoint = endpoint
        self.apiVersion = apiVersion
        self.maxTokens = maxTokens
        self.maxRetries = maxRetries
        self.requestTimeout = requestTimeout
    }

    public func extractStatement(
        text: String,
        hints: ExtractionHints
    ) async throws -> ExtractionResult {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }

        let body = makeRequestBody(redactedText: text, hints: hints)
        let request = try makeURLRequest(body: body)

        let (data, http) = try await sendWithRetries(request)
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.network(
                statusCode: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        let response = try decodeResponse(data)
        let extracted = try extractToolCall(response)

        let inputTokens     = response.usage?.input_tokens ?? 0
        let outputTokens    = response.usage?.output_tokens ?? 0
        let cacheReadTokens = response.usage?.cache_read_input_tokens
        let costUSD = Pricing.costUSD(
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens ?? 0
        )

        return ExtractionResult(
            statement: extracted,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            costUSD: costUSD,
            promptVersion: ExtractionPromptV1.version
        )
    }

    // MARK: - Request building

    func makeURLRequest(body: Data) throws -> URLRequest {
        var req = URLRequest(url: endpoint, timeoutInterval: requestTimeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        req.httpBody = body
        return req
    }

    func makeRequestBody(redactedText: String, hints: ExtractionHints) -> Data {
        // Build the JSON manually so we get fine-grained control over the
        // `cache_control` blocks (which JSONEncoder makes awkward).
        let toolSchemaObject = (try? JSONSerialization.jsonObject(
            with: ExtractionPromptV1.toolSchemaJSON.data(using: .utf8)!
        )) as? [String: Any] ?? [:]

        let userText: String = {
            var lines = ["Statement text below. Call the tool exactly once with the structured extraction."]
            if !hints.knownIssuers.isEmpty {
                lines.append("Known issuers: " + hints.knownIssuers.joined(separator: ", "))
            }
            lines.append("---")
            lines.append(redactedText)
            return lines.joined(separator: "\n")
        }()

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": [
                [
                    "type": "text",
                    "text": ExtractionPromptV1.systemPrompt,
                    "cache_control": ["type": "ephemeral"],
                ]
            ],
            "tools": [
                [
                    "name": ExtractionPromptV1.toolName,
                    "description": ExtractionPromptV1.toolDescription,
                    "input_schema": toolSchemaObject,
                ]
            ],
            "tool_choice": [
                "type": "tool",
                "name": ExtractionPromptV1.toolName,
            ],
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": userText],
                    ],
                ],
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: - Response decoding

    struct AnthropicResponse: Decodable {
        let id: String?
        let model: String?
        let stop_reason: String?
        let content: [ContentBlock]
        let usage: Usage?
    }

    enum ContentBlock: Decodable {
        case text(String)
        case toolUse(name: String, input: Data)

        private enum CodingKeys: String, CodingKey { case type, text, name, input }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(String.self, forKey: .type)
            switch type {
            case "text":
                self = .text((try? c.decode(String.self, forKey: .text)) ?? "")
            case "tool_use":
                let name = try c.decode(String.self, forKey: .name)
                // `input` is an arbitrary JSON object — re-serialize so we
                // can hand the raw bytes to ExtractedStatement's decoder.
                let raw = try c.decode(JSONValue.self, forKey: .input)
                let data = try JSONSerialization.data(withJSONObject: raw.asAny)
                self = .toolUse(name: name, input: data)
            default:
                self = .text("")
            }
        }
    }

    struct Usage: Decodable {
        let input_tokens: Int
        let output_tokens: Int
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
    }

    func decodeResponse(_ data: Data) throws -> AnthropicResponse {
        do {
            return try JSONDecoder().decode(AnthropicResponse.self, from: data)
        } catch {
            throw LLMError.decoding("AnthropicProvider response: \(error)")
        }
    }

    func extractToolCall(_ response: AnthropicResponse) throws -> ExtractedStatement {
        for block in response.content {
            if case let .toolUse(name, input) = block, name == ExtractionPromptV1.toolName {
                do {
                    return try ExtractedStatement.makeJSONDecoder()
                        .decode(ExtractedStatement.self, from: input)
                } catch {
                    let snippet = String(data: input.prefix(1200), encoding: .utf8) ?? "<non-UTF8 \(input.count) bytes>"
                    throw LLMError.decoding(
                        "tool_use input → ExtractedStatement: \(error)\n--- raw input (first 1200 bytes) ---\n\(snippet)"
                    )
                }
            }
        }
        throw LLMError.toolCallNotReturned
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
        throw LLMError.network(statusCode: 0, body: "no transport response")
    }

    /// Exponential backoff: 250ms, 500ms, 1s, 2s, ... bounded at 8s.
    func backoffNanos(attempt: Int) -> UInt64 {
        let base: Double = 0.25
        let capped = min(base * pow(2.0, Double(attempt - 1)), 8.0)
        return UInt64(capped * 1_000_000_000)
    }
}

// MARK: - Tiny JSON tree

/// Minimal `Decodable` walker that preserves nested JSON structure so the
/// `tool_use.input` block can be re-serialized as raw JSON bytes for our
/// stricter `ExtractedStatement.makeJSONDecoder()`.
private enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case integer(Int)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .integer(i)
        } else if let d = try? c.decode(Double.self) {
            self = .number(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "unrecognised JSON node"
            )
        }
    }

    var asAny: Any {
        switch self {
        case .null:           return NSNull()
        case .bool(let b):    return b
        case .integer(let i): return i
        case .number(let n):  return n
        case .string(let s):  return s
        case .array(let a):   return a.map(\.asAny)
        case .object(let o):
            var dict: [String: Any] = [:]
            for (k, v) in o { dict[k] = v.asAny }
            return dict
        }
    }
}
