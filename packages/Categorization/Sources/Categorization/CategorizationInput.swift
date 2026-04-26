import Foundation
import Domain

/// What every strategy needs to make a decision. Built once per transaction
/// at import time (or on demand for re-categorization).
///
/// `bankName` is the issuing bank from the parent `Account` — used by the
/// bank-category-mapping strategy to prefer issuer-specific rows over
/// wildcard rows. `transactionId` is `nil` during import (the row hasn't been
/// inserted yet); it's populated when re-categorizing an existing row.
public struct CategorizationInput: Sendable {
    public let transactionId: Int64?
    public let merchantNormalized: String
    public let merchantId: Int64?
    public let bankCategoryRaw: String?
    public let bankName: String?
    public let amount: Money
    public let fingerprint: String

    public init(
        transactionId: Int64? = nil,
        merchantNormalized: String,
        merchantId: Int64? = nil,
        bankCategoryRaw: String? = nil,
        bankName: String? = nil,
        amount: Money,
        fingerprint: String
    ) {
        self.transactionId = transactionId
        self.merchantNormalized = merchantNormalized
        self.merchantId = merchantId
        self.bankCategoryRaw = bankCategoryRaw
        self.bankName = bankName
        self.amount = amount
        self.fingerprint = fingerprint
    }
}

/// A single strategy in the priority chain. Returns `nil` to fall through to
/// the next strategy.
public protocol CategorizationStrategy: Sendable {
    var reason: CategorizationReason { get }
    func categorize(_ input: CategorizationInput) async throws -> CategorizationSuggestion?
}
