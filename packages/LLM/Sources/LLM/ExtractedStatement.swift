import Foundation
import Domain

/// The Codable contract returned by `LLMProvider.extractStatement`.
///
/// Mirrors the JSON tool-schema in `docs/llm-integration.md`. Lives in the
/// `LLM` package — not `Domain` — because it is provider-bound (the schema is
/// what the model is told to return).
public struct ExtractedStatement: Codable, Hashable, Sendable {
    public var statement: Header
    public var cards: [CardRow]
    public var transactions: [TransactionRow]
    public var warnings: [String]

    public init(
        statement: Header,
        cards: [CardRow],
        transactions: [TransactionRow],
        warnings: [String] = []
    ) {
        self.statement = statement
        self.cards = cards
        self.transactions = transactions
        self.warnings = warnings
    }

    enum CodingKeys: String, CodingKey {
        case statement, cards, transactions, warnings
    }

    /// Tolerant decoder: arrays default to `[]` when the model omits them
    /// entirely. The schema marks them required, but Anthropic's tool-use
    /// validator can still let an incomplete object through, and surfacing
    /// "missing key" was masking the real problem (usually OCR text the
    /// model couldn't parse). Downstream `ExtractionValidator` catches the
    /// "no rows but a non-zero total" case.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.statement    = try c.decode(Header.self, forKey: .statement)
        self.cards        = try c.decodeIfPresent([CardRow].self, forKey: .cards) ?? []
        self.transactions = try c.decodeIfPresent([TransactionRow].self, forKey: .transactions) ?? []
        self.warnings     = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }

    public struct Header: Codable, Hashable, Sendable {
        public var issuer: String
        public var product: String?
        public var periodStart: Date?
        public var periodEnd: Date?
        public var dueDate: Date?
        public var currency: Currency
        public var totals: Totals

        public init(
            issuer: String,
            product: String? = nil,
            periodStart: Date? = nil,
            periodEnd: Date? = nil,
            dueDate: Date? = nil,
            currency: Currency,
            totals: Totals
        ) {
            self.issuer = issuer
            self.product = product
            self.periodStart = periodStart
            self.periodEnd = periodEnd
            self.dueDate = dueDate
            self.currency = currency
            self.totals = totals
        }

        enum CodingKeys: String, CodingKey {
            case issuer, product
            case periodStart = "period_start"
            case periodEnd = "period_end"
            case dueDate = "due_date"
            case currency, totals
        }
    }

    public struct Totals: Codable, Hashable, Sendable {
        public var previousBalance: Decimal?
        public var paymentReceived: Decimal?
        public var revolvingBalance: Decimal?
        /// Matches "Total dos lançamentos atuais".
        public var currentChargesTotal: Decimal

        public init(
            previousBalance: Decimal? = nil,
            paymentReceived: Decimal? = nil,
            revolvingBalance: Decimal? = nil,
            currentChargesTotal: Decimal
        ) {
            self.previousBalance = previousBalance
            self.paymentReceived = paymentReceived
            self.revolvingBalance = revolvingBalance
            self.currentChargesTotal = currentChargesTotal
        }

        enum CodingKeys: String, CodingKey {
            case previousBalance = "previous_balance"
            case paymentReceived = "payment_received"
            case revolvingBalance = "revolving_balance"
            case currentChargesTotal = "current_charges_total"
        }
    }

    public struct CardRow: Codable, Hashable, Sendable {
        public var last4: String
        public var holderName: String
        public var network: String?
        public var tier: String?
        /// Matches "Lançamentos no cartão (final XXXX)".
        public var subtotal: Decimal

        public init(
            last4: String,
            holderName: String,
            network: String? = nil,
            tier: String? = nil,
            subtotal: Decimal
        ) {
            self.last4 = last4
            self.holderName = holderName
            self.network = network
            self.tier = tier
            self.subtotal = subtotal
        }

        enum CodingKeys: String, CodingKey {
            case last4
            case holderName = "holder_name"
            case network, tier, subtotal
        }
    }

    public struct TransactionRow: Codable, Hashable, Sendable {
        public var cardLast4: String
        public var postedDate: Date
        public var postedYearInferred: Bool
        public var rawDescription: String
        public var merchant: String
        public var merchantCity: String?
        public var bankCategoryRaw: String?
        public var amount: Decimal
        public var currency: Currency
        public var originalAmount: Decimal?
        public var originalCurrency: Currency?
        public var fxRate: Decimal?
        public var installmentCurrent: Int?
        public var installmentTotal: Int?
        public var purchaseMethod: PurchaseMethod
        public var transactionType: TransactionType
        public var confidence: Double

        public init(
            cardLast4: String,
            postedDate: Date,
            postedYearInferred: Bool,
            rawDescription: String,
            merchant: String,
            merchantCity: String? = nil,
            bankCategoryRaw: String? = nil,
            amount: Decimal,
            currency: Currency,
            originalAmount: Decimal? = nil,
            originalCurrency: Currency? = nil,
            fxRate: Decimal? = nil,
            installmentCurrent: Int? = nil,
            installmentTotal: Int? = nil,
            purchaseMethod: PurchaseMethod,
            transactionType: TransactionType,
            confidence: Double
        ) {
            self.cardLast4 = cardLast4
            self.postedDate = postedDate
            self.postedYearInferred = postedYearInferred
            self.rawDescription = rawDescription
            self.merchant = merchant
            self.merchantCity = merchantCity
            self.bankCategoryRaw = bankCategoryRaw
            self.amount = amount
            self.currency = currency
            self.originalAmount = originalAmount
            self.originalCurrency = originalCurrency
            self.fxRate = fxRate
            self.installmentCurrent = installmentCurrent
            self.installmentTotal = installmentTotal
            self.purchaseMethod = purchaseMethod
            self.transactionType = transactionType
            self.confidence = confidence
        }

        enum CodingKeys: String, CodingKey {
            case cardLast4 = "card_last4"
            case postedDate = "posted_date"
            case postedYearInferred = "posted_year_inferred"
            case rawDescription = "raw_description"
            case merchant
            case merchantCity = "merchant_city"
            case bankCategoryRaw = "bank_category_raw"
            case amount, currency
            case originalAmount = "original_amount"
            case originalCurrency = "original_currency"
            case fxRate = "fx_rate"
            case installmentCurrent = "installment_current"
            case installmentTotal = "installment_total"
            case purchaseMethod = "purchase_method"
            case transactionType = "transaction_type"
            case confidence
        }
    }
}

// MARK: - JSON helpers

extension ExtractedStatement {
    /// Date strategy for the statement DTO is plain ISO yyyy-MM-dd. Decimal
    /// values arrive as JSON numbers — `Decimal` Codable handles them.
    public static func makeJSONDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        d.dateDecodingStrategy = .formatted(formatter)
        return d
    }

    public static func makeJSONEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        e.dateEncodingStrategy = .formatted(formatter)
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
