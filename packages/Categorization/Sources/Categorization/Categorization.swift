import Foundation

/// Namespace for the `Categorization` package. Phase 2 ships:
///
/// - `CategorizationEngine` — runs strategies in priority order.
/// - `CategorizationStrategy` protocol + concrete strategies for each slot.
/// - `CategorizationInput` — DTO each strategy consumes.
///
/// See `docs/categorization.md` for the priority chain and confidence bands.
public enum Categorization {
    public static let phase = "v0.2"
}
