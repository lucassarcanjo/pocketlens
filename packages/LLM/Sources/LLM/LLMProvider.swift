import Foundation
import Domain

/// Hints carried into an extraction call. Phase 1 only carries locale + a
/// list of issuer fingerprints we already know about (e.g., `"Itaú Personnalité"`)
/// so the model can short-circuit identification.
public struct ExtractionHints: Sendable, Hashable {
    public var locale: Locale
    public var knownIssuers: [String]

    public init(locale: Locale = Locale(identifier: "pt_BR"), knownIssuers: [String] = []) {
        self.locale = locale
        self.knownIssuers = knownIssuers
    }
}

/// What an extraction call returns: the structured payload plus the
/// provider-side cost accounting we stamp on `ImportBatch`.
public struct ExtractionResult: Sendable, Hashable {
    public var statement: ExtractedStatement
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int?
    public var costUSD: Double
    public var promptVersion: String

    public init(
        statement: ExtractedStatement,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int? = nil,
        costUSD: Double,
        promptVersion: String
    ) {
        self.statement = statement
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.costUSD = costUSD
        self.promptVersion = promptVersion
    }
}

/// What an LLM provider must do to be plugged into the import pipeline.
///
/// Categorize / summarize methods are reserved for Phase 2 and Phase 5 and
/// intentionally not on this protocol yet — keeping the surface minimal until
/// we actually need to ship them.
public protocol LLMProvider: Sendable {
    var kind: LLMProviderKind { get }
    var model: String { get }

    func extractStatement(
        text: String,
        hints: ExtractionHints
    ) async throws -> ExtractionResult
}

/// Errors any provider might surface. Mocked + real providers throw the same
/// cases so the upstream import pipeline only needs one set of catches.
public enum LLMError: Error, Equatable, Sendable {
    case missingAPIKey
    case network(statusCode: Int, body: String)
    case decoding(String)
    case toolCallNotReturned
    case canceled
}

extension LLMError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Anthropic API key is missing. Add one in Settings."
        case .network(let status, let body):
            let snippet = body.prefix(400)
            return "Anthropic HTTP \(status): \(snippet)"
        case .decoding(let detail):
            return "Anthropic response couldn't be decoded: \(detail)"
        case .toolCallNotReturned:
            return "Anthropic returned no `record_extracted_statement` tool call. The model may have refused or hit max_tokens."
        case .canceled:
            return "The Anthropic request was cancelled."
        }
    }
}
