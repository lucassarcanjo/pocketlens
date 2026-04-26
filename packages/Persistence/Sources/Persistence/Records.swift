import Foundation
import GRDB
import Domain

/// GRDB record types for the v1 schema.
///
/// Records hold raw column values (snake_case TEXT/INTEGER as on disk) and
/// know how to bridge to/from their `Domain` counterparts. Repositories use
/// records for all read/write — never `Domain` types directly.

// MARK: - Date helpers

enum DateFmt {
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}

// MARK: - AccountRecord

struct AccountRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "accounts"
    var id: Int64?
    var bankName: String
    var holderName: String
    var accountAlias: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case bankName = "bank_name"
        case holderName = "holder_name"
        case accountAlias = "account_alias"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    init(from a: Account) {
        self.id = a.id
        self.bankName = a.bankName
        self.holderName = a.holderName
        self.accountAlias = a.accountAlias
        self.createdAt = DateFmt.iso8601.string(from: a.createdAt)
        self.updatedAt = DateFmt.iso8601.string(from: a.updatedAt)
    }

    func toDomain() -> Account {
        Account(
            id: id,
            bankName: bankName,
            holderName: holderName,
            accountAlias: accountAlias,
            createdAt: DateFmt.iso8601.date(from: createdAt) ?? Date(),
            updatedAt: DateFmt.iso8601.date(from: updatedAt) ?? Date()
        )
    }
}

// MARK: - CardRecord

struct CardRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "cards"
    var id: Int64?
    var accountId: Int64
    var last4: String
    var holderName: String
    var network: String?
    var tier: String?
    var nickname: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case last4
        case holderName = "holder_name"
        case network, tier, nickname
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    init(from c: Card, accountId: Int64) {
        self.id = c.id
        self.accountId = accountId
        self.last4 = c.last4
        self.holderName = c.holderName
        self.network = c.network
        self.tier = c.tier
        self.nickname = c.nickname
        self.createdAt = DateFmt.iso8601.string(from: c.createdAt)
        self.updatedAt = DateFmt.iso8601.string(from: c.updatedAt)
    }

    func toDomain() -> Card {
        Card(
            id: id,
            accountId: accountId,
            last4: last4,
            holderName: holderName,
            network: network,
            tier: tier,
            nickname: nickname,
            createdAt: DateFmt.iso8601.date(from: createdAt) ?? Date(),
            updatedAt: DateFmt.iso8601.date(from: updatedAt) ?? Date()
        )
    }
}

// MARK: - MerchantRecord

struct MerchantRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "merchants"
    var id: Int64?
    var raw: String
    var normalized: String
    var defaultCategoryId: Int64?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, raw, normalized
        case defaultCategoryId = "default_category_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    init(from m: Merchant) {
        self.id = m.id
        self.raw = m.raw
        self.normalized = m.normalized
        self.defaultCategoryId = m.defaultCategoryId
        self.createdAt = DateFmt.iso8601.string(from: m.createdAt)
        self.updatedAt = DateFmt.iso8601.string(from: m.updatedAt)
    }

    func toDomain() -> Merchant {
        Merchant(
            id: id,
            raw: raw,
            normalized: normalized,
            defaultCategoryId: defaultCategoryId,
            createdAt: DateFmt.iso8601.date(from: createdAt) ?? Date(),
            updatedAt: DateFmt.iso8601.date(from: updatedAt) ?? Date()
        )
    }
}

// MARK: - CategoryRecord

struct CategoryRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "categories"
    var id: Int64?
    var name: String
    var parentId: Int64?
    var color: String?
    var icon: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case parentId = "parent_id"
        case color, icon
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    init(from c: Domain.Category) {
        self.id = c.id
        self.name = c.name
        self.parentId = c.parentId
        self.color = c.color
        self.icon = c.icon
        self.createdAt = DateFmt.iso8601.string(from: c.createdAt)
        self.updatedAt = DateFmt.iso8601.string(from: c.updatedAt)
    }

    func toDomain() -> Domain.Category {
        Domain.Category(
            id: id,
            parentId: parentId,
            name: name,
            color: color,
            icon: icon,
            createdAt: DateFmt.iso8601.date(from: createdAt) ?? Date(),
            updatedAt: DateFmt.iso8601.date(from: updatedAt) ?? Date()
        )
    }
}

// MARK: - ImportBatchRecord

struct ImportBatchRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "import_batches"
    var id: Int64?
    var sourceFileName: String
    var sourceFileSha256: String
    var sourcePages: Int
    var statementPeriodStart: String?
    var statementPeriodEnd: String?
    var statementCloseDate: String?
    var statementDueDate: String?
    var statementTotal: Int
    var previousBalance: Int?
    var paymentReceived: Int?
    var revolvingBalance: Int?
    var currency: String
    var llmProvider: String
    var llmModel: String
    var llmPromptVersion: String
    var llmInputTokens: Int
    var llmOutputTokens: Int
    var llmCacheReadTokens: Int?
    var llmCostUsd: Double
    var validationStatus: String
    var parseWarnings: String?
    var status: String
    var importedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case sourceFileName = "source_file_name"
        case sourceFileSha256 = "source_file_sha256"
        case sourcePages = "source_pages"
        case statementPeriodStart = "statement_period_start"
        case statementPeriodEnd = "statement_period_end"
        case statementCloseDate = "statement_close_date"
        case statementDueDate = "statement_due_date"
        case statementTotal = "statement_total"
        case previousBalance = "previous_balance"
        case paymentReceived = "payment_received"
        case revolvingBalance = "revolving_balance"
        case currency
        case llmProvider = "llm_provider"
        case llmModel = "llm_model"
        case llmPromptVersion = "llm_prompt_version"
        case llmInputTokens = "llm_input_tokens"
        case llmOutputTokens = "llm_output_tokens"
        case llmCacheReadTokens = "llm_cache_read_tokens"
        case llmCostUsd = "llm_cost_usd"
        case validationStatus = "validation_status"
        case parseWarnings = "parse_warnings"
        case status
        case importedAt = "imported_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    init(from b: ImportBatch) {
        self.id = b.id
        self.sourceFileName = b.sourceFileName
        self.sourceFileSha256 = b.sourceFileSha256
        self.sourcePages = b.sourcePages
        self.statementPeriodStart = b.statementPeriodStart.map(DateFmt.date.string(from:))
        self.statementPeriodEnd   = b.statementPeriodEnd.map(DateFmt.date.string(from:))
        self.statementCloseDate   = b.statementCloseDate.map(DateFmt.date.string(from:))
        self.statementDueDate     = b.statementDueDate.map(DateFmt.date.string(from:))
        self.statementTotal       = b.statementTotal.minorUnits
        self.previousBalance      = b.previousBalance?.minorUnits
        self.paymentReceived      = b.paymentReceived?.minorUnits
        self.revolvingBalance     = b.revolvingBalance?.minorUnits
        self.currency             = b.statementTotal.currency.rawValue
        self.llmProvider          = b.llmProvider.rawValue
        self.llmModel             = b.llmModel
        self.llmPromptVersion     = b.llmPromptVersion
        self.llmInputTokens       = b.llmInputTokens
        self.llmOutputTokens      = b.llmOutputTokens
        self.llmCacheReadTokens   = b.llmCacheReadTokens
        self.llmCostUsd           = b.llmCostUSD
        self.validationStatus     = b.validationStatus.rawValue
        self.parseWarnings        = ImportBatchRecord.encodeWarnings(b.parseWarnings)
        self.status               = b.status.rawValue
        self.importedAt           = DateFmt.iso8601.string(from: b.importedAt)
    }

    func toDomain() -> ImportBatch {
        let cur = Currency(rawValue: currency) ?? .BRL
        return ImportBatch(
            id: id,
            sourceFileName: sourceFileName,
            sourceFileSha256: sourceFileSha256,
            sourcePages: sourcePages,
            statementPeriodStart: statementPeriodStart.flatMap(DateFmt.date.date(from:)),
            statementPeriodEnd: statementPeriodEnd.flatMap(DateFmt.date.date(from:)),
            statementCloseDate: statementCloseDate.flatMap(DateFmt.date.date(from:)),
            statementDueDate: statementDueDate.flatMap(DateFmt.date.date(from:)),
            statementTotal: Money(minorUnits: statementTotal, currency: cur),
            previousBalance: previousBalance.map { Money(minorUnits: $0, currency: cur) },
            paymentReceived: paymentReceived.map { Money(minorUnits: $0, currency: cur) },
            revolvingBalance: revolvingBalance.map { Money(minorUnits: $0, currency: cur) },
            llmProvider: LLMProviderKind(rawValue: llmProvider) ?? .mock,
            llmModel: llmModel,
            llmPromptVersion: llmPromptVersion,
            llmInputTokens: llmInputTokens,
            llmOutputTokens: llmOutputTokens,
            llmCacheReadTokens: llmCacheReadTokens,
            llmCostUSD: llmCostUsd,
            validationStatus: ValidationStatus(rawValue: validationStatus) ?? .ok,
            parseWarnings: ImportBatchRecord.decodeWarnings(parseWarnings),
            status: BatchStatus(rawValue: status) ?? .completed,
            importedAt: DateFmt.iso8601.date(from: importedAt) ?? Date()
        )
    }

    private static func encodeWarnings(_ warnings: [String]) -> String? {
        guard !warnings.isEmpty else { return nil }
        let data = (try? JSONEncoder().encode(warnings)) ?? Data()
        return String(data: data, encoding: .utf8)
    }

    private static func decodeWarnings(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

// MARK: - TransactionRecord

struct TransactionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transactions"
    var id: Int64?
    var importBatchId: Int64
    var cardId: Int64
    var merchantId: Int64?
    var categoryId: Int64?
    var postedDate: String
    var postedYearInferred: Int
    var rawDescription: String
    var merchantNormalized: String
    var merchantCity: String?
    var bankCategoryRaw: String?
    var amount: Int
    var currency: String
    var originalAmount: Int?
    var originalCurrency: String?
    var fxRate: Double?
    var installmentCurrent: Int?
    var installmentTotal: Int?
    var purchaseMethod: String
    var transactionType: String
    var confidence: Double
    var categorizationReason: String?
    var fingerprint: String
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case importBatchId = "import_batch_id"
        case cardId = "card_id"
        case merchantId = "merchant_id"
        case categoryId = "category_id"
        case postedDate = "posted_date"
        case postedYearInferred = "posted_year_inferred"
        case rawDescription = "raw_description"
        case merchantNormalized = "merchant_normalized"
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
        case categorizationReason = "categorization_reason"
        case fingerprint
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    init(from t: Transaction, fingerprint: String, importBatchId: Int64, cardId: Int64, merchantId: Int64?) {
        self.id = t.id
        self.importBatchId = importBatchId
        self.cardId = cardId
        self.merchantId = merchantId
        self.categoryId = t.categoryId
        self.postedDate = DateFmt.date.string(from: t.postedDate)
        self.postedYearInferred = t.postedYearInferred ? 1 : 0
        self.rawDescription = t.rawDescription
        self.merchantNormalized = t.merchantNormalized
        self.merchantCity = t.merchantCity
        self.bankCategoryRaw = t.bankCategoryRaw
        self.amount = t.amount.minorUnits
        self.currency = t.amount.currency.rawValue
        self.originalAmount = t.originalAmount?.minorUnits
        self.originalCurrency = t.originalAmount?.currency.rawValue
        self.fxRate = (t.fxRate as NSDecimalNumber?)?.doubleValue
        self.installmentCurrent = t.installment?.current
        self.installmentTotal = t.installment?.total
        self.purchaseMethod = t.purchaseMethod.rawValue
        self.transactionType = t.transactionType.rawValue
        self.confidence = t.confidence
        self.categorizationReason = t.categorizationReason.isEmpty ? nil : t.categorizationReason
        self.fingerprint = fingerprint
        self.createdAt = DateFmt.iso8601.string(from: t.createdAt)
        self.updatedAt = DateFmt.iso8601.string(from: t.updatedAt)
    }

    func toDomain() -> Transaction {
        let cur = Currency(rawValue: currency) ?? .BRL
        let originalMoney: Money? = {
            guard
                let amt = originalAmount,
                let oc = originalCurrency,
                let parsed = Currency(rawValue: oc)
            else { return nil }
            return Money(minorUnits: amt, currency: parsed)
        }()
        let installment: Installment? = {
            guard
                let cur = installmentCurrent,
                let total = installmentTotal
            else { return nil }
            return Installment(current: cur, total: total)
        }()
        return Transaction(
            id: id,
            importBatchId: importBatchId,
            cardId: cardId,
            merchantId: merchantId,
            categoryId: categoryId,
            postedDate: DateFmt.date.date(from: postedDate) ?? Date(timeIntervalSince1970: 0),
            postedYearInferred: postedYearInferred != 0,
            rawDescription: rawDescription,
            merchantNormalized: merchantNormalized,
            merchantCity: merchantCity,
            bankCategoryRaw: bankCategoryRaw,
            amount: Money(minorUnits: amount, currency: cur),
            originalAmount: originalMoney,
            fxRate: fxRate.map { Decimal($0) },
            installment: installment,
            purchaseMethod: PurchaseMethod(rawValue: purchaseMethod) ?? .unknown,
            transactionType: TransactionType(rawValue: transactionType) ?? .purchase,
            confidence: confidence,
            categorizationReason: categorizationReason ?? "",
            createdAt: DateFmt.iso8601.date(from: createdAt) ?? Date(),
            updatedAt: DateFmt.iso8601.date(from: updatedAt) ?? Date()
        )
    }
}
