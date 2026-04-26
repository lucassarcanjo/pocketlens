import Foundation

/// The result of running the categorization chain on a single transaction.
/// `categoryId == nil` means "uncategorized" — confidence is `0.0` and the
/// reason is `.uncategorized`.
public struct CategorizationSuggestion: Hashable, Codable, Sendable {
    public var categoryId: Int64?
    public var confidence: Double
    public var reason: CategorizationReason
    /// Human-readable phrase suitable for UI display
    /// (e.g., `"Matched merchant alias: Uber"`).
    public var explanation: String

    public init(
        categoryId: Int64?,
        confidence: Double,
        reason: CategorizationReason,
        explanation: String
    ) {
        self.categoryId = categoryId
        self.confidence = confidence
        self.reason = reason
        self.explanation = explanation
    }

    public static let uncategorized = CategorizationSuggestion(
        categoryId: nil,
        confidence: 0.0,
        reason: .uncategorized,
        explanation: "No strong rule found"
    )
}
