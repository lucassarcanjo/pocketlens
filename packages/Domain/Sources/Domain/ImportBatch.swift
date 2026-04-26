import Foundation

/// Provenance + headers of a single statement import. One row per file ever
/// imported. Carries enough metadata that we can reconstruct what the LLM
/// did, what it cost, and whether the math checked out.
public struct ImportBatch: Hashable, Codable, Sendable, Identifiable {
    public var id: Int64?

    public var sourceFileName: String
    /// SHA-256 of the raw PDF bytes. Used as the file-level dedup key —
    /// re-importing the same file is rejected.
    public var sourceFileSha256: String
    public var sourcePages: Int

    public var statementPeriodStart: Date?
    public var statementPeriodEnd: Date?
    public var statementCloseDate: Date?
    public var statementDueDate: Date?

    public var statementTotal: Money
    public var previousBalance: Money?
    public var paymentReceived: Money?
    public var revolvingBalance: Money?

    public var llmProvider: LLMProviderKind
    public var llmModel: String
    /// Stamp of the prompt revision used. When this drifts we know to
    /// re-validate fixtures.
    public var llmPromptVersion: String
    public var llmInputTokens: Int
    public var llmOutputTokens: Int
    public var llmCacheReadTokens: Int?
    public var llmCostUSD: Double

    public var validationStatus: ValidationStatus
    public var parseWarnings: [String]
    public var status: BatchStatus
    public var importedAt: Date

    public init(
        id: Int64? = nil,
        sourceFileName: String,
        sourceFileSha256: String,
        sourcePages: Int,
        statementPeriodStart: Date? = nil,
        statementPeriodEnd: Date? = nil,
        statementCloseDate: Date? = nil,
        statementDueDate: Date? = nil,
        statementTotal: Money,
        previousBalance: Money? = nil,
        paymentReceived: Money? = nil,
        revolvingBalance: Money? = nil,
        llmProvider: LLMProviderKind,
        llmModel: String,
        llmPromptVersion: String,
        llmInputTokens: Int,
        llmOutputTokens: Int,
        llmCacheReadTokens: Int? = nil,
        llmCostUSD: Double,
        validationStatus: ValidationStatus,
        parseWarnings: [String] = [],
        status: BatchStatus = .completed,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.sourceFileName = sourceFileName
        self.sourceFileSha256 = sourceFileSha256
        self.sourcePages = sourcePages
        self.statementPeriodStart = statementPeriodStart
        self.statementPeriodEnd = statementPeriodEnd
        self.statementCloseDate = statementCloseDate
        self.statementDueDate = statementDueDate
        self.statementTotal = statementTotal
        self.previousBalance = previousBalance
        self.paymentReceived = paymentReceived
        self.revolvingBalance = revolvingBalance
        self.llmProvider = llmProvider
        self.llmModel = llmModel
        self.llmPromptVersion = llmPromptVersion
        self.llmInputTokens = llmInputTokens
        self.llmOutputTokens = llmOutputTokens
        self.llmCacheReadTokens = llmCacheReadTokens
        self.llmCostUSD = llmCostUSD
        self.validationStatus = validationStatus
        self.parseWarnings = parseWarnings
        self.status = status
        self.importedAt = importedAt
    }
}

public enum BatchStatus: String, Codable, CaseIterable, Sendable, Hashable {
    case pending
    case completed
    case failed
}
