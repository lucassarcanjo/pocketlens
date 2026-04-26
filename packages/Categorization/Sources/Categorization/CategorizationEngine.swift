import Foundation
import Domain
import Persistence
import LLM

/// Runs categorization strategies in priority order; first non-nil wins.
///
/// The order in `strategies` is the priority chain — see
/// `docs/categorization.md`. `standard(...)` wires the production order using
/// persistence-backed strategies. Tests can pass an alternate order or
/// substitute mocks.
public struct CategorizationEngine: Sendable {
    public let strategies: [any CategorizationStrategy]

    public init(strategies: [any CategorizationStrategy]) {
        self.strategies = strategies
    }

    /// Walk the chain. The result is always defined: if every strategy returns
    /// nil, we return `.uncategorized` with confidence `0.0`.
    public func categorize(_ input: CategorizationInput) async throws -> CategorizationSuggestion {
        for strategy in strategies {
            if let suggestion = try await strategy.categorize(input) {
                return suggestion
            }
        }
        return .uncategorized
    }

    // MARK: - Production wiring

    /// Wire all eight production strategies in priority order against the
    /// shared `SQLiteStore`. Phase 5 will swap the LLM stub for a real
    /// provider call.
    public static func standard(store: SQLiteStore) -> CategorizationEngine {
        CategorizationEngine(strategies: [
            UserCorrectionStrategy(store: store),
            MerchantAliasStrategy(store: store),
            RuleStrategy(store: store, source: .user, reason: .userRule, baseConfidence: 0.90),
            BankCategoryStrategy(store: store),
            RuleStrategy(store: store, source: .system, reason: .keywordRule, baseConfidence: 0.80),
            SimilarityStrategy(store: store),
            LLMSuggestionStrategy(),  // Phase 5 placeholder.
        ])
    }
}
