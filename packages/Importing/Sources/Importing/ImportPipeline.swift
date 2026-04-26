import Foundation
import Domain
import LLM

/// End-to-end import orchestrator.
///
/// `dryRun(...)` walks the full flow up to (but not including) the database
/// write: PDF → Mistral OCR → redacted markdown → LLM extraction → validation
/// → normalization → deduplication → `ImportPlan`. The Phase 1 SwiftUI app
/// calls `dryRun` then hands the plan to a persistence step; tests can assert
/// on the plan via `makePlan` without making any network calls.
public struct ImportPipeline: Sendable {

    public enum Error: Swift.Error, Equatable, Sendable {
        case unreadable(String)
        case validationFailed(reasons: [String])
        case ocrUnavailable
    }

    public let provider: any LLMProvider
    public let ocr: MistralOCRClient?
    public let redactor: Redactor
    public let validator: ExtractionValidator
    public let dedup: DeduplicationEngine

    /// Bank-name fallback when the LLM doesn't surface an issuer string.
    /// Phase 1 only writes Itaú statements; the seeder (Phase 6 task) adds
    /// rows to the `accounts` table when the importer encounters a new bank.
    public let defaultBankName: String

    public init(
        provider: any LLMProvider,
        ocr: MistralOCRClient? = nil,
        redactor: Redactor = Redactor(),
        validator: ExtractionValidator = ExtractionValidator(),
        dedup: DeduplicationEngine = DeduplicationEngine(),
        defaultBankName: String = "Itaú"
    ) {
        self.provider = provider
        self.ocr = ocr
        self.redactor = redactor
        self.validator = validator
        self.dedup = dedup
        self.defaultBankName = defaultBankName
    }

    public func dryRun(
        url: URL,
        sourceFileName: String? = nil,
        hints: ExtractionHints = ExtractionHints()
    ) async throws -> ImportPlan {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try await dryRun(
            data: data,
            sourceFileName: sourceFileName ?? url.lastPathComponent,
            hints: hints
        )
    }

    public func dryRun(
        data: Data,
        sourceFileName: String,
        hints: ExtractionHints = ExtractionHints()
    ) async throws -> ImportPlan {
        guard let ocr else { throw Error.ocrUnavailable }
        let sha = FileHash.sha256(of: data)
        let ocrOutput = try await ocr.extract(data: data)
        let redacted = redactor.redact(ocrOutput.combined)

        let extraction = try await provider.extractStatement(text: redacted, hints: hints)
        let report = validator.validate(extraction.statement)

        return makePlan(
            extraction: extraction,
            report: report,
            sha256: sha,
            sourceFileName: sourceFileName,
            sourcePages: ocrOutput.pageCount
        )
    }

    /// Build a plan from an already-loaded extraction. Useful for tests that
    /// drive the pipeline with `MockLLMProvider` and don't need PDFKit on
    /// the path.
    public func makePlan(
        extraction: ExtractionResult,
        report: ExtractionValidator.Report,
        sha256: String,
        sourceFileName: String,
        sourcePages: Int
    ) -> ImportPlan {
        let s = extraction.statement
        let currency = s.statement.currency

        // Cards: one Domain.Card per CardRow.
        let cards: [Card] = s.cards.map { row in
            Card(
                last4: row.last4,
                holderName: row.holderName,
                network: row.network,
                tier: row.tier
            )
        }

        // Build merchant rows — dedup by normalized name within this batch.
        var merchantsByNormalized: [String: Merchant] = [:]
        var pending: [PendingTransaction] = []
        pending.reserveCapacity(s.transactions.count)

        for row in s.transactions {
            let normalized = MerchantNormalizer.normalize(row.merchant)
            if merchantsByNormalized[normalized] == nil {
                merchantsByNormalized[normalized] = Merchant(
                    raw: row.merchant,
                    normalized: normalized
                )
            }

            let installment: Installment? = {
                guard
                    let cur = row.installmentCurrent,
                    let total = row.installmentTotal
                else { return nil }
                return Installment(current: cur, total: total)
            }()

            let amount = Money(major: row.amount, currency: row.currency)
            let originalAmount: Money? = {
                guard
                    let amt = row.originalAmount,
                    let oc = row.originalCurrency
                else { return nil }
                return Money(major: amt, currency: oc)
            }()

            let tx = Transaction(
                postedDate: row.postedDate,
                postedYearInferred: row.postedYearInferred,
                rawDescription: row.rawDescription,
                merchantNormalized: normalized,
                merchantCity: row.merchantCity,
                bankCategoryRaw: row.bankCategoryRaw,
                amount: amount,
                originalAmount: originalAmount,
                fxRate: row.fxRate,
                installment: installment,
                purchaseMethod: row.purchaseMethod,
                transactionType: row.transactionType,
                confidence: row.confidence
            )
            let fingerprint = tx.fingerprint(cardLast4: row.cardLast4)

            pending.append(PendingTransaction(
                cardLast4: row.cardLast4,
                merchantNormalized: normalized,
                transaction: tx,
                fingerprint: fingerprint
            ))
        }

        let dedupResult = dedup.collapse(pending)

        var warnings = report.warnings
        if dedupResult.collapsed > 0 {
            warnings.insert(
                "Collapsed \(dedupResult.collapsed) duplicate row(s) within this batch.",
                at: 0
            )
        }

        let batch = ImportBatch(
            sourceFileName: sourceFileName,
            sourceFileSha256: sha256,
            sourcePages: sourcePages,
            statementPeriodStart: s.statement.periodStart,
            statementPeriodEnd: s.statement.periodEnd,
            statementCloseDate: s.statement.periodEnd,
            statementDueDate: s.statement.dueDate,
            statementTotal: Money(major: s.statement.totals.currentChargesTotal, currency: currency),
            previousBalance: s.statement.totals.previousBalance.map {
                Money(major: $0, currency: currency)
            },
            paymentReceived: s.statement.totals.paymentReceived.map {
                Money(major: $0, currency: currency)
            },
            revolvingBalance: s.statement.totals.revolvingBalance.map {
                Money(major: $0, currency: currency)
            },
            llmProvider: provider.kind,
            llmModel: provider.model,
            llmPromptVersion: extraction.promptVersion,
            llmInputTokens: extraction.inputTokens,
            llmOutputTokens: extraction.outputTokens,
            llmCacheReadTokens: extraction.cacheReadTokens,
            llmCostUSD: extraction.costUSD,
            validationStatus: report.status,
            parseWarnings: warnings,
            status: report.status == .failed ? .failed : .completed
        )

        let merchantsOrdered = s.transactions
            .map { MerchantNormalizer.normalize($0.merchant) }
            .reduce(into: [String]()) { acc, n in
                if !acc.contains(n) { acc.append(n) }
            }
            .compactMap { merchantsByNormalized[$0] }

        return ImportPlan(
            batch: batch,
            cards: cards,
            merchants: merchantsOrdered,
            transactions: dedupResult.unique
        )
    }
}
