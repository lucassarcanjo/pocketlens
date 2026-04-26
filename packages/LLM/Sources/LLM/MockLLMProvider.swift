import Foundation
import Domain

/// Deterministic provider for tests and previews. Hands back a canned
/// `ExtractedStatement` regardless of input text. Two construction modes:
///
///   1. `MockLLMProvider(canned:)` — pass the DTO directly (useful when a
///      test wants to mutate one field).
///   2. `MockLLMProvider(jsonResource:in:)` — load a JSON resource from a
///      bundle. Used by `LLMTests` and the import-pipeline end-to-end test.
public struct MockLLMProvider: LLMProvider {
    public let kind: LLMProviderKind = .mock
    public let model: String
    public let promptVersion: String

    private let canned: ExtractedStatement
    private let inputTokens: Int
    private let outputTokens: Int
    private let costUSD: Double

    public init(
        canned: ExtractedStatement,
        model: String = "mock-1",
        promptVersion: String = ExtractionPromptV1.version,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        costUSD: Double = 0
    ) {
        self.canned = canned
        self.model = model
        self.promptVersion = promptVersion
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
    }

    public init(
        jsonResource name: String,
        in bundle: Bundle,
        model: String = "mock-1",
        promptVersion: String = ExtractionPromptV1.version
    ) throws {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw LLMError.decoding(
                "MockLLMProvider: resource \(name).json not found in \(bundle.bundlePath)"
            )
        }
        let data = try Data(contentsOf: url)
        let decoder = ExtractedStatement.makeJSONDecoder()
        do {
            self.canned = try decoder.decode(ExtractedStatement.self, from: data)
        } catch {
            throw LLMError.decoding("MockLLMProvider: \(error)")
        }
        self.model = model
        self.promptVersion = promptVersion
        self.inputTokens = 0
        self.outputTokens = 0
        self.costUSD = 0
    }

    public func extractStatement(
        text: String,
        hints: ExtractionHints
    ) async throws -> ExtractionResult {
        ExtractionResult(
            statement: canned,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: nil,
            costUSD: costUSD,
            promptVersion: promptVersion
        )
    }
}
