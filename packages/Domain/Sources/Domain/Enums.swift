import Foundation

/// Type of a single ledger entry on a credit-card statement.
///
/// `iof` is split out because Itaú lists it as a distinct line that we want to
/// expose to the user as its own row (rather than fold into the originating
/// purchase). `payment` is the customer's bill payment. `adjustment` is a
/// catch-all for issuer corrections we don't want to misclassify.
public enum TransactionType: String, Codable, CaseIterable, Sendable, Hashable {
    case purchase
    case refund
    case payment
    case fee
    case iof
    case adjustment
}

/// How a purchase was made — drives icon rendering and (later) categorisation
/// priors. `unknown` is acceptable: PDFKit can't always recover the @-glyph
/// or wallet icon and we'd rather flag uncertainty than guess.
public enum PurchaseMethod: String, Codable, CaseIterable, Sendable, Hashable {
    case physical
    case virtualCard = "virtual_card"
    case digitalWallet = "digital_wallet"
    case recurring
    case unknown
}

/// `current` of `total` — `Installment(current: 6, total: 10)` is "parcela 6/10".
public struct Installment: Hashable, Codable, Sendable {
    public let current: Int
    public let total: Int

    public init(current: Int, total: Int) {
        precondition(current >= 1, "installment.current must be >= 1, got \(current)")
        precondition(total >= 1, "installment.total must be >= 1, got \(total)")
        precondition(current <= total, "installment.current (\(current)) > total (\(total))")
        self.current = current
        self.total = total
    }
}

/// Validation outcome of an import — drives UI badges on `ImportsView`.
public enum ValidationStatus: String, Codable, CaseIterable, Sendable, Hashable {
    case ok
    case warning
    case failed
}

/// Where the LLM extraction came from. Stamped on every `ImportBatch` so we
/// can audit which model produced what and detect prompt drift later.
public enum LLMProviderKind: String, Codable, CaseIterable, Sendable, Hashable {
    case anthropic
    case mock
    /// Reserved for Phase 5.
    case ollama
    /// Reserved for Phase 5.
    case openai
}
