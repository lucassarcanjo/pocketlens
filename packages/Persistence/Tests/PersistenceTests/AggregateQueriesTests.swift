import XCTest
@testable import Persistence
import Domain

final class AggregateQueriesTests: XCTestCase {

    // MARK: - Date helpers

    /// UTC `yyyy-MM-dd` parser — matches `DateFmt.date` in the production code.
    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private func d(_ s: String) -> Date { Self.ymd.date(from: s)! }

    // March 2026 = primary period under test.
    private var marchStart: Date { d("2026-03-01") }
    private var aprilStart: Date { d("2026-04-01") }

    // MARK: - Fixture

    /// Seeds: 1 account, 2 cards, default categories, 1 batch, and a curated
    /// set of transactions spanning the period boundary, mixed currencies,
    /// purchases / refunds / fees / IOF / payments, and varied categorization
    /// confidences.
    private struct Fixture {
        let store: SQLiteStore
        let card1Id: Int64   // last4 0001
        let card2Id: Int64   // last4 0002
        let alimentacaoId: Int64
        let transporteId: Int64
    }

    private func makeFixture() async throws -> Fixture {
        let store = try SQLiteStore.makeInMemory()
        try DefaultDataSeeder.seed(into: store)

        let acctRepo = AccountRepository(store: store)
        let cardRepo = CardRepository(store: store)
        let batchRepo = ImportBatchRepository(store: store)
        let txRepo = TransactionRepository(store: store)
        let catRepo = CategoryRepository(store: store)

        let acct = try await acctRepo.findOrCreate(bankName: "Itaú", holderName: "JOHN")
        let card1 = try await cardRepo.upsert(
            Card(last4: "0001", holderName: "JOHN", network: "Mastercard", tier: "Black"),
            accountId: acct.id!
        )
        let card2 = try await cardRepo.upsert(
            Card(last4: "0002", holderName: "FAMILIA", nickname: "Family"),
            accountId: acct.id!
        )

        let cats = try await catRepo.all()
        let alimentacao = cats.first { $0.name == "Alimentação" }!
        let transporte  = cats.first { $0.name == "Transporte" }!

        let batch = try await batchRepo.insert(ImportBatch(
            sourceFileName: "fixture.pdf",
            sourceFileSha256: "sha-fixture",
            sourcePages: 1,
            statementTotal: Money(major: 0, currency: .BRL),
            llmProvider: .mock, llmModel: "m", llmPromptVersion: "v1",
            llmInputTokens: 0, llmOutputTokens: 0, llmCostUSD: 0,
            validationStatus: .ok
        ))
        let batchId = batch.id!

        // Helper to insert a transaction with a deterministic fingerprint.
        func insert(
            _ description: String,
            amount: Money,
            on date: Date,
            type: TransactionType,
            cardId: Int64,
            cardLast4: String,
            categoryId: Int64?,
            confidence: Double
        ) async throws {
            let tx = Transaction(
                categoryId: categoryId,
                postedDate: date,
                rawDescription: description,
                merchantNormalized: description.lowercased(),
                amount: amount,
                transactionType: type,
                confidence: confidence
            )
            let fp = tx.fingerprint(cardLast4: cardLast4)
            _ = try await txRepo.insert(
                tx, fingerprint: fp,
                importBatchId: batchId, cardId: cardId, merchantId: nil
            )
        }

        // In-period BRL purchases
        try await insert("Padaria Real",  amount: Money(major: 25.50,  currency: .BRL),
                         on: d("2026-03-05"), type: .purchase,
                         cardId: card1.id!, cardLast4: "0001",
                         categoryId: alimentacao.id, confidence: 0.95)
        try await insert("Posto Shell",   amount: Money(major: 200.00, currency: .BRL),
                         on: d("2026-03-10"), type: .purchase,
                         cardId: card1.id!, cardLast4: "0001",
                         categoryId: transporte.id, confidence: 0.85)
        try await insert("Restaurante",   amount: Money(major: 80.00,  currency: .BRL),
                         on: d("2026-03-25"), type: .purchase,
                         cardId: card1.id!, cardLast4: "0001",
                         categoryId: alimentacao.id, confidence: 0.65)
        // Refund (negative) — offsets Alimentação total
        try await insert("Padaria Estorno", amount: Money(major: -30.00, currency: .BRL),
                         on: d("2026-03-22"), type: .refund,
                         cardId: card1.id!, cardLast4: "0001",
                         categoryId: alimentacao.id, confidence: 0.95)
        // IOF — uncategorized, BRL, on card 2
        try await insert("IOF",           amount: Money(major: 5.00,   currency: .BRL),
                         on: d("2026-03-20"), type: .iof,
                         cardId: card2.id!, cardLast4: "0002",
                         categoryId: nil, confidence: 0.0)
        // USD purchase — different currency, uncategorized, low conf
        try await insert("Amazon US",     amount: Money(major: 50.00,  currency: .USD),
                         on: d("2026-03-15"), type: .purchase,
                         cardId: card2.id!, cardLast4: "0002",
                         categoryId: nil, confidence: 0.40)
        // Payment — must NOT count as spending
        try await insert("Pagamento",     amount: Money(major: -2000.00, currency: .BRL),
                         on: d("2026-03-28"), type: .payment,
                         cardId: card1.id!, cardLast4: "0001",
                         categoryId: nil, confidence: 0.0)

        // Boundary: exactly on marchStart — included.
        try await insert("Boundary Start", amount: Money(major: 1.00, currency: .BRL),
                         on: d("2026-03-01"), type: .purchase,
                         cardId: card1.id!, cardLast4: "0001",
                         categoryId: alimentacao.id, confidence: 0.95)
        // Boundary: exactly on aprilStart — excluded (endExclusive).
        try await insert("Boundary End",   amount: Money(major: 999.00, currency: .BRL),
                         on: d("2026-04-01"), type: .purchase,
                         cardId: card1.id!, cardLast4: "0001",
                         categoryId: alimentacao.id, confidence: 0.95)
        // Outside: before period.
        try await insert("Old Tx",         amount: Money(major: 999.00, currency: .BRL),
                         on: d("2026-02-28"), type: .purchase,
                         cardId: card1.id!, cardLast4: "0001",
                         categoryId: alimentacao.id, confidence: 0.95)

        return Fixture(
            store: store,
            card1Id: card1.id!,
            card2Id: card2.id!,
            alimentacaoId: alimentacao.id!,
            transporteId: transporte.id!
        )
    }

    // MARK: - Tests

    func testTotalsByCurrency_GroupsAndExcludesPayments() async throws {
        let f = try await makeFixture()
        let q = AggregateQueries(store: f.store)

        let totals = try await q.totalsByCurrency(start: marchStart, endExclusive: aprilStart)
        // BRL: 1 + 25.50 + 200 + 80 + 5 - 30 = 281.50
        // USD: 50.00
        // Payment (-2000) and out-of-period rows are excluded.
        XCTAssertEqual(totals.count, 2)
        let brl = totals.first { $0.currency == .BRL }!
        let usd = totals.first { $0.currency == .USD }!
        XCTAssertEqual(brl.total.minorUnits, 28150)
        XCTAssertEqual(usd.total.minorUnits, 5000)
    }

    func testSpendingByCategory_BRL_IncludesUncategorizedBucket() async throws {
        let f = try await makeFixture()
        let q = AggregateQueries(store: f.store)

        let rows = try await q.spendingByCategory(
            start: marchStart, endExclusive: aprilStart, currency: .BRL
        )
        // Alimentação: 1 + 25.50 + 80 - 30 = 76.50 (count=4)
        // Transporte: 200 (count=1)
        // Uncategorized: IOF 5 (count=1)
        XCTAssertEqual(rows.count, 3)
        let aliment = rows.first { $0.categoryId == f.alimentacaoId }!
        XCTAssertEqual(aliment.total.minorUnits, 7650)
        XCTAssertEqual(aliment.transactionCount, 4)
        let transp = rows.first { $0.categoryId == f.transporteId }!
        XCTAssertEqual(transp.total.minorUnits, 20000)
        let uncat = rows.first { $0.categoryId == nil }!
        XCTAssertEqual(uncat.total.minorUnits, 500)
        XCTAssertEqual(uncat.transactionCount, 1)
        XCTAssertNil(uncat.categoryName)
    }

    func testTopMerchants_BRL_OrderedByTotalDesc_LimitApplied() async throws {
        let f = try await makeFixture()
        let q = AggregateQueries(store: f.store)

        let rows = try await q.topMerchants(
            start: marchStart, endExclusive: aprilStart, currency: .BRL, limit: 2
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].merchantNormalized, "posto shell")
        XCTAssertEqual(rows[0].total.minorUnits, 20000)
        XCTAssertEqual(rows[1].merchantNormalized, "restaurante")
        XCTAssertEqual(rows[1].total.minorUnits, 8000)
    }

    func testLargestTransactions_ExcludesRefundsAndPayments() async throws {
        let f = try await makeFixture()
        let q = AggregateQueries(store: f.store)

        let rows = try await q.largestTransactions(
            start: marchStart, endExclusive: aprilStart, currency: .BRL, limit: 10
        )
        let descriptions = rows.map { $0.merchantNormalized }
        XCTAssertFalse(descriptions.contains("padaria estorno"), "refunds excluded")
        XCTAssertFalse(descriptions.contains("pagamento"), "payments excluded")
        // Order: posto (200) > restaurante (80) > padaria real (25.50) > iof (5) > boundary start (1)
        XCTAssertEqual(rows.first?.merchantNormalized, "posto shell")
        XCTAssertEqual(rows.first?.amount.minorUnits, 20000)
        XCTAssertEqual(rows.first?.cardLast4, "0001")
    }

    func testUncategorizedCount_CountsAcrossCurrencies() async throws {
        let f = try await makeFixture()
        let q = AggregateQueries(store: f.store)

        let count = try await q.uncategorizedCount(start: marchStart, endExclusive: aprilStart)
        // Uncategorized in spending types: IOF (BRL), Amazon US (USD).
        // The payment is uncategorized but excluded by transaction_type.
        XCTAssertEqual(count, 2)
    }

    func testNeedsReviewCount_DefaultBand_0_50_to_0_80() async throws {
        let f = try await makeFixture()
        let q = AggregateQueries(store: f.store)

        let count = try await q.needsReviewCount(start: marchStart, endExclusive: aprilStart)
        // Restaurante at 0.65 → in band, has category → counted.
        // Posto at 0.85 → above band.
        // Padaria/refund/boundary at 0.95 → above band.
        // Amazon at 0.40 → below band AND no category.
        // IOF at 0.0 → no category.
        XCTAssertEqual(count, 1)
    }

    func testTotalsByCard_BRL() async throws {
        let f = try await makeFixture()
        let q = AggregateQueries(store: f.store)

        let rows = try await q.totalsByCard(
            start: marchStart, endExclusive: aprilStart, currency: .BRL
        )
        // Card 0001 BRL: 1 + 25.50 + 200 + 80 - 30 = 276.50
        // Card 0002 BRL: 5 (IOF only)
        XCTAssertEqual(rows.count, 2)
        let c1 = rows.first { $0.cardId == f.card1Id }!
        XCTAssertEqual(c1.total.minorUnits, 27650)
        XCTAssertEqual(c1.cardLast4, "0001")
        let c2 = rows.first { $0.cardId == f.card2Id }!
        XCTAssertEqual(c2.total.minorUnits, 500)
        XCTAssertEqual(c2.cardNickname, "Family")
    }

    func testMonthBoundary_StartInclusive_EndExclusive() async throws {
        let f = try await makeFixture()
        let q = AggregateQueries(store: f.store)

        // Single-day period containing only the boundary-start row (R$1.00).
        let oneDay = try await q.totalsByCurrency(
            start: marchStart, endExclusive: d("2026-03-02")
        )
        XCTAssertEqual(oneDay.count, 1)
        XCTAssertEqual(oneDay.first?.total.minorUnits, 100)

        // April 1st must NOT be included in the March period.
        let march = try await q.spendingByCategory(
            start: marchStart, endExclusive: aprilStart, currency: .BRL
        )
        XCTAssertFalse(
            march.contains { $0.transactionCount > 0 && $0.total.minorUnits == 99900 },
            "boundary-end row at 2026-04-01 must not appear in March"
        )
    }

    /// A 3-installment purchase imported across 3 statements must show one
    /// installment in each statement's month — *not* three in the original
    /// purchase month. Bucketing key is `import_batches.statement_period_end`.
    func testInstallments_BucketByStatementMonth_NotPostedDate() async throws {
        let store = try SQLiteStore.makeInMemory()
        try DefaultDataSeeder.seed(into: store)

        let acctRepo = AccountRepository(store: store)
        let cardRepo = CardRepository(store: store)
        let batchRepo = ImportBatchRepository(store: store)
        let txRepo = TransactionRepository(store: store)

        let acct = try await acctRepo.findOrCreate(bankName: "Itaú", holderName: "JOHN")
        let card = try await cardRepo.upsert(
            Card(last4: "9999", holderName: "JOHN"),
            accountId: acct.id!
        )

        func makeBatch(sha: String, periodEnd: Date) async throws -> Int64 {
            let b = try await batchRepo.insert(ImportBatch(
                sourceFileName: "stmt-\(sha).pdf",
                sourceFileSha256: sha,
                sourcePages: 1,
                statementPeriodEnd: periodEnd,
                statementTotal: Money(major: 0, currency: .BRL),
                llmProvider: .mock, llmModel: "m", llmPromptVersion: "v1",
                llmInputTokens: 0, llmOutputTokens: 0, llmCostUSD: 0,
                validationStatus: .ok
            ))
            return b.id!
        }
        // Three statements, one month apart.
        let marchBatch = try await makeBatch(sha: "sha-march", periodEnd: d("2026-03-25"))
        let aprilBatch = try await makeBatch(sha: "sha-april", periodEnd: d("2026-04-25"))
        let mayBatch   = try await makeBatch(sha: "sha-may",   periodEnd: d("2026-05-25"))

        // Same hotel purchase in February, paid 3x of R$100 across statements.
        // Each row carries the original purchase date as `postedDate` — the
        // bug was that this date drove the dashboard buckets.
        func insertInstallment(batchId: Int64, current: Int) async throws {
            let tx = Transaction(
                postedDate: d("2026-02-15"),
                rawDescription: "HOTEL XYZ \(current)/3",
                merchantNormalized: "hotel xyz",
                amount: Money(major: 100.00, currency: .BRL),
                installment: Installment(current: current, total: 3),
                transactionType: .purchase,
                confidence: 0.95
            )
            let fp = tx.fingerprint(cardLast4: "9999")
            _ = try await txRepo.insert(
                tx, fingerprint: fp,
                importBatchId: batchId, cardId: card.id!, merchantId: nil
            )
        }
        try await insertInstallment(batchId: marchBatch, current: 1)
        try await insertInstallment(batchId: aprilBatch, current: 2)
        try await insertInstallment(batchId: mayBatch,   current: 3)

        let q = AggregateQueries(store: store)

        // March: only installment 1/3
        let march = try await q.totalsByCurrency(
            start: d("2026-03-01"), endExclusive: d("2026-04-01")
        )
        XCTAssertEqual(march.first { $0.currency == .BRL }?.total.minorUnits, 10000)

        // April: only installment 2/3
        let april = try await q.totalsByCurrency(
            start: d("2026-04-01"), endExclusive: d("2026-05-01")
        )
        XCTAssertEqual(april.first { $0.currency == .BRL }?.total.minorUnits, 10000)

        // May: only installment 3/3
        let may = try await q.totalsByCurrency(
            start: d("2026-05-01"), endExclusive: d("2026-06-01")
        )
        XCTAssertEqual(may.first { $0.currency == .BRL }?.total.minorUnits, 10000)

        // February (the original purchase month) has no statement, so nothing
        // is bucketed there — the previous behavior would have piled all
        // R$300 here.
        let feb = try await q.totalsByCurrency(
            start: d("2026-02-01"), endExclusive: d("2026-03-01")
        )
        XCTAssertTrue(feb.isEmpty)

        // Other dashboard surfaces follow the same bucketing.
        let aprilByCard = try await q.totalsByCard(
            start: d("2026-04-01"), endExclusive: d("2026-05-01"), currency: .BRL
        )
        XCTAssertEqual(aprilByCard.first?.total.minorUnits, 10000)
        XCTAssertEqual(aprilByCard.first?.cardLast4, "9999")
    }

    func testEmptyPeriod_ReturnsEmptyArraysAndZero() async throws {
        let f = try await makeFixture()
        let q = AggregateQueries(store: f.store)

        let emptyStart = d("2025-01-01")
        let emptyEnd   = d("2025-02-01")

        let totals = try await q.totalsByCurrency(start: emptyStart, endExclusive: emptyEnd)
        XCTAssertTrue(totals.isEmpty)

        let cats = try await q.spendingByCategory(
            start: emptyStart, endExclusive: emptyEnd, currency: .BRL
        )
        XCTAssertTrue(cats.isEmpty)

        let merchants = try await q.topMerchants(
            start: emptyStart, endExclusive: emptyEnd, currency: .BRL, limit: 5
        )
        XCTAssertTrue(merchants.isEmpty)

        let largest = try await q.largestTransactions(
            start: emptyStart, endExclusive: emptyEnd, currency: .BRL, limit: 5
        )
        XCTAssertTrue(largest.isEmpty)

        let uncat = try await q.uncategorizedCount(start: emptyStart, endExclusive: emptyEnd)
        XCTAssertEqual(uncat, 0)

        let needs = try await q.needsReviewCount(start: emptyStart, endExclusive: emptyEnd)
        XCTAssertEqual(needs, 0)

        let cards = try await q.totalsByCard(
            start: emptyStart, endExclusive: emptyEnd, currency: .BRL
        )
        XCTAssertTrue(cards.isEmpty)
    }
}
