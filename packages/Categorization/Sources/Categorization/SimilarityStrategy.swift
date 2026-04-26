import Foundation
import Domain
import Persistence

/// Slot 6 — similarity to a previously-categorized transaction.
///
/// Uses Jaccard similarity over character bigrams of `merchant_normalized`.
/// Bigrams are robust to small variations ("uber trip" vs "uber trips") and
/// don't need stemming/tokenization tuning per language. We compare against
/// every already-categorized transaction; the best match's similarity is
/// scaled into the 0.50–0.85 confidence band.
///
/// Threshold is 0.85 by default (per `docs/categorization.md`). Below
/// threshold → fall through. Tune against real data.
public struct SimilarityStrategy: CategorizationStrategy {
    public let reason: CategorizationReason = .similarity
    let store: SQLiteStore
    let threshold: Double

    public init(store: SQLiteStore, threshold: Double = 0.85) {
        self.store = store
        self.threshold = threshold
    }

    public func categorize(_ input: CategorizationInput) async throws -> CategorizationSuggestion? {
        let txRepo = TransactionRepository(store: store)
        let categorized = try await txRepo.categorized()
        guard !categorized.isEmpty else { return nil }

        let inputBigrams = Self.bigrams(of: input.merchantNormalized)
        guard !inputBigrams.isEmpty else { return nil }

        var bestScore: Double = 0
        var bestMatch: Transaction?

        for tx in categorized {
            // Trivial early-out: identical normalized strings are a hit.
            if tx.merchantNormalized == input.merchantNormalized,
               let categoryId = tx.categoryId
            {
                return CategorizationSuggestion(
                    categoryId: categoryId,
                    confidence: 0.85,
                    reason: .similarity,
                    explanation: "Similar to: \(tx.merchantNormalized)"
                )
            }
            let score = Self.jaccard(inputBigrams, Self.bigrams(of: tx.merchantNormalized))
            if score > bestScore {
                bestScore = score
                bestMatch = tx
            }
        }

        guard
            bestScore >= threshold,
            let match = bestMatch,
            let categoryId = match.categoryId
        else { return nil }

        // Scale [threshold, 1.0] → [0.50, 0.85].
        let clamped = max(threshold, min(1.0, bestScore))
        let span = max(1e-9, 1.0 - threshold)
        let confidence = 0.50 + (clamped - threshold) / span * (0.85 - 0.50)

        return CategorizationSuggestion(
            categoryId: categoryId,
            confidence: confidence,
            reason: .similarity,
            explanation: "Similar to: \(match.merchantNormalized)"
        )
    }

    // MARK: - Bigram helpers

    static func bigrams(of s: String) -> Set<String> {
        let chars = Array(s)
        guard chars.count >= 2 else { return [] }
        var out = Set<String>()
        out.reserveCapacity(chars.count - 1)
        for i in 0..<(chars.count - 1) {
            out.insert(String(chars[i...i+1]))
        }
        return out
    }

    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty && b.isEmpty { return 0 }
        let inter = a.intersection(b).count
        let union = a.union(b).count
        return Double(inter) / Double(union)
    }
}
