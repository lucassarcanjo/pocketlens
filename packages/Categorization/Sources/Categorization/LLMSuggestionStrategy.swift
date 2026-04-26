import Foundation
import Domain

/// Slot 7 — Phase-5 LLM categorization suggestion.
///
/// Phase 2 stub: returns nil so the chain falls through to `.uncategorized`.
/// Phase 5 wires this to `LLMProvider.categorize(...)` with caching against
/// `merchant_normalized`.
public struct LLMSuggestionStrategy: CategorizationStrategy {
    public let reason: CategorizationReason = .llmSuggestion

    public init() {}

    public func categorize(_ input: CategorizationInput) async throws -> CategorizationSuggestion? {
        nil
    }
}
