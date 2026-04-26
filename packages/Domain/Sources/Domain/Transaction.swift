import Foundation
import CryptoKit

/// One imported statement line. Fingerprint-deduped at the row level.
public struct Transaction: Hashable, Codable, Sendable, Identifiable {
    public var id: Int64?
    public var importBatchId: Int64?
    public var cardId: Int64?
    public var merchantId: Int64?
    public var categoryId: Int64?

    public var postedDate: Date
    /// True when the statement printed only DD/MM and the year was inferred
    /// from the statement period + (for installments) `current/total`.
    public var postedYearInferred: Bool

    public var rawDescription: String
    public var merchantNormalized: String
    public var merchantCity: String?
    public var bankCategoryRaw: String?

    /// Always stored in BRL (or whatever the statement currency is). For
    /// international transactions the home-currency converted amount lives
    /// here and the original is preserved in `originalAmount`.
    public var amount: Money
    public var originalAmount: Money?
    public var fxRate: Decimal?

    public var installment: Installment?
    public var purchaseMethod: PurchaseMethod
    public var transactionType: TransactionType

    public var confidence: Double
    /// Phase 2 fills this. Empty in Phase 1.
    public var categorizationReason: String

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        importBatchId: Int64? = nil,
        cardId: Int64? = nil,
        merchantId: Int64? = nil,
        categoryId: Int64? = nil,
        postedDate: Date,
        postedYearInferred: Bool = false,
        rawDescription: String,
        merchantNormalized: String,
        merchantCity: String? = nil,
        bankCategoryRaw: String? = nil,
        amount: Money,
        originalAmount: Money? = nil,
        fxRate: Decimal? = nil,
        installment: Installment? = nil,
        purchaseMethod: PurchaseMethod = .unknown,
        transactionType: TransactionType = .purchase,
        confidence: Double = 1.0,
        categorizationReason: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.importBatchId = importBatchId
        self.cardId = cardId
        self.merchantId = merchantId
        self.categoryId = categoryId
        self.postedDate = postedDate
        self.postedYearInferred = postedYearInferred
        self.rawDescription = rawDescription
        self.merchantNormalized = merchantNormalized
        self.merchantCity = merchantCity
        self.bankCategoryRaw = bankCategoryRaw
        self.amount = amount
        self.originalAmount = originalAmount
        self.fxRate = fxRate
        self.installment = installment
        self.purchaseMethod = purchaseMethod
        self.transactionType = transactionType
        self.confidence = confidence
        self.categorizationReason = categorizationReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Fingerprint

extension Transaction {
    /// Deterministic SHA-1 hex digest for transaction-level dedup.
    ///
    /// The shape mirrors `docs/data-model.md` §"Fingerprint":
    /// `posted_date | merchant_normalized | amount | currency | card_last4
    ///  | installment_current | installment_total | purchase_method`
    ///
    /// `cardLast4` is taken as a parameter because `Card` lookups happen at
    /// persistence time but fingerprint must be computable from the parsed
    /// row alone (so tests can verify it without a DB).
    public func fingerprint(cardLast4: String) -> String {
        let parts: [String] = [
            Self.dateFormatter.string(from: postedDate),
            merchantNormalized,
            String(amount.minorUnits),
            amount.currency.rawValue,
            cardLast4,
            installment.map { String($0.current) } ?? "",
            installment.map { String($0.total) } ?? "",
            purchaseMethod.rawValue,
        ]
        let joined = parts.joined(separator: "|")
        let digest = Insecure.SHA1.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
