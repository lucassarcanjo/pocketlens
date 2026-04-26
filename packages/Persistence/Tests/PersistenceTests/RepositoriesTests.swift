import XCTest
@testable import Persistence
import Domain

final class RepositoriesTests: XCTestCase {

    private func makeStore() throws -> SQLiteStore {
        try SQLiteStore.makeInMemory()
    }

    // MARK: - AccountRepository

    func testAccount_FindOrCreate_RoundTrip() async throws {
        let store = try makeStore()
        let repo = AccountRepository(store: store)
        let a = try await repo.findOrCreate(bankName: "Itaú", holderName: "JOHN")
        XCTAssertNotNil(a.id)
        let again = try await repo.findOrCreate(bankName: "Itaú", holderName: "JOHN")
        XCTAssertEqual(a.id, again.id, "second call must reuse the row")
    }

    // MARK: - CardRepository

    func testCard_UpsertReusesByLast4() async throws {
        let store = try makeStore()
        let acctRepo = AccountRepository(store: store)
        let cardRepo = CardRepository(store: store)
        let acct = try await acctRepo.findOrCreate(bankName: "Itaú", holderName: "JOHN")
        let acctId = acct.id!

        let c1 = try await cardRepo.upsert(
            Card(last4: "1111", holderName: "JOHN", network: "Mastercard", tier: "Black"),
            accountId: acctId
        )
        let c2 = try await cardRepo.upsert(
            Card(last4: "1111", holderName: "JOHN"),
            accountId: acctId
        )
        XCTAssertEqual(c1.id, c2.id)
        let all = try await cardRepo.all()
        XCTAssertEqual(all.count, 1)
    }

    // MARK: - MerchantRepository

    func testMerchant_UpsertByNormalized() async throws {
        let store = try makeStore()
        let repo = MerchantRepository(store: store)
        _ = try await repo.upsert(Merchant(raw: "UBER *TRIP", normalized: "uber *trip"))
        _ = try await repo.upsert(Merchant(raw: "UBER * TRIP", normalized: "uber *trip"))
        let all = try await repo.all()
        XCTAssertEqual(all.count, 1)
    }

    // MARK: - ImportBatch + Transactions full round-trip

    func testFullRoundTrip() async throws {
        let store = try makeStore()
        try DefaultDataSeeder.seed(into: store)

        let acctRepo = AccountRepository(store: store)
        let cardRepo = CardRepository(store: store)
        let merchantRepo = MerchantRepository(store: store)
        let batchRepo = ImportBatchRepository(store: store)
        let txRepo = TransactionRepository(store: store)

        let acct = try await acctRepo.findOrCreate(bankName: "Itaú", holderName: "JOHN")
        let card = try await cardRepo.upsert(
            Card(last4: "1111", holderName: "JOHN"),
            accountId: acct.id!
        )
        let merchant = try await merchantRepo.upsert(
            Merchant(raw: "PADARIA REAL", normalized: "padaria real")
        )

        let batch = ImportBatch(
            sourceFileName: "test.pdf",
            sourceFileSha256: "abc",
            sourcePages: 5,
            statementTotal: Money(major: 100, currency: .BRL),
            llmProvider: .mock,
            llmModel: "mock-1",
            llmPromptVersion: "v1",
            llmInputTokens: 0,
            llmOutputTokens: 0,
            llmCostUSD: 0,
            validationStatus: .ok
        )
        let inserted = try await batchRepo.insert(batch)
        XCTAssertNotNil(inserted.id)

        // SHA-256 dedup lookup.
        let foundBySha = try await batchRepo.findBySha256("abc")
        XCTAssertEqual(foundBySha?.id, inserted.id)

        // Insert a transaction.
        let tx = Transaction(
            postedDate: Date(timeIntervalSince1970: 1700000000),
            rawDescription: "PADARIA REAL",
            merchantNormalized: "padaria real",
            amount: Money(major: 25.50, currency: .BRL),
            purchaseMethod: .physical,
            transactionType: .purchase,
            confidence: 0.99
        )
        let fp = tx.fingerprint(cardLast4: "1111")
        let savedTx = try await txRepo.insert(
            tx, fingerprint: fp,
            importBatchId: inserted.id!,
            cardId: card.id!,
            merchantId: merchant.id!
        )
        XCTAssertNotNil(savedTx.id)
        XCTAssertEqual(savedTx.amount.minorUnits, 2550)
        XCTAssertEqual(savedTx.amount.currency, .BRL)
        XCTAssertEqual(savedTx.purchaseMethod, .physical)

        // List by batch.
        let inBatch = try await txRepo.forBatch(inserted.id!)
        XCTAssertEqual(inBatch.count, 1)
    }

    func testTransactionFingerprintUniqueConstraintEnforcedAtDB() async throws {
        let store = try makeStore()
        let acctRepo = AccountRepository(store: store)
        let cardRepo = CardRepository(store: store)
        let batchRepo = ImportBatchRepository(store: store)
        let txRepo = TransactionRepository(store: store)
        let acct = try await acctRepo.findOrCreate(bankName: "Itaú", holderName: "L")
        let card = try await cardRepo.upsert(Card(last4: "0001", holderName: "L"), accountId: acct.id!)
        let batch = try await batchRepo.insert(ImportBatch(
            sourceFileName: "x.pdf",
            sourceFileSha256: "x",
            sourcePages: 1,
            statementTotal: Money(major: 0, currency: .BRL),
            llmProvider: .mock,
            llmModel: "m",
            llmPromptVersion: "v1",
            llmInputTokens: 0, llmOutputTokens: 0, llmCostUSD: 0,
            validationStatus: .ok
        ))
        let tx = Transaction(
            postedDate: Date(timeIntervalSince1970: 0),
            rawDescription: "X",
            merchantNormalized: "x",
            amount: Money(major: 1, currency: .BRL)
        )
        let fp = tx.fingerprint(cardLast4: "0001")
        _ = try await txRepo.insert(
            tx, fingerprint: fp,
            importBatchId: batch.id!, cardId: card.id!, merchantId: nil
        )
        do {
            _ = try await txRepo.insert(
                tx, fingerprint: fp,
                importBatchId: batch.id!, cardId: card.id!, merchantId: nil
            )
            XCTFail("expected unique-constraint failure")
        } catch {
            // Expected — UNIQUE(fingerprint).
        }
    }

    // MARK: - Monthly pagination

    func testInMonth_PagesAndBoundsHonorPostedDate() async throws {
        let store = try makeStore()
        let acctRepo = AccountRepository(store: store)
        let cardRepo = CardRepository(store: store)
        let batchRepo = ImportBatchRepository(store: store)
        let txRepo = TransactionRepository(store: store)

        let acct = try await acctRepo.findOrCreate(bankName: "Itaú", holderName: "L")
        let card = try await cardRepo.upsert(Card(last4: "0001", holderName: "L"), accountId: acct.id!)
        let batch = try await batchRepo.insert(ImportBatch(
            sourceFileName: "x.pdf",
            sourceFileSha256: "month-pagination",
            sourcePages: 1,
            statementTotal: Money(major: 0, currency: .BRL),
            llmProvider: .mock,
            llmModel: "m",
            llmPromptVersion: "v1",
            llmInputTokens: 0, llmOutputTokens: 0, llmCostUSD: 0,
            validationStatus: .ok
        ))

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let aprilStart = cal.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        let mayStart   = cal.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let juneStart  = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!

        // 5 in April, 3 in May. Insert in mixed order to verify ordering.
        let dates: [Date] = [
            cal.date(byAdding: .day, value: 14, to: aprilStart)!, // Apr 15
            cal.date(byAdding: .day, value: 1,  to: mayStart)!,   // May 2
            cal.date(byAdding: .day, value: 0,  to: aprilStart)!, // Apr 1
            cal.date(byAdding: .day, value: 29, to: aprilStart)!, // Apr 30
            cal.date(byAdding: .day, value: 4,  to: mayStart)!,   // May 5
            cal.date(byAdding: .day, value: 9,  to: aprilStart)!, // Apr 10
            cal.date(byAdding: .day, value: 19, to: aprilStart)!, // Apr 20
            cal.date(byAdding: .day, value: 9,  to: mayStart)!    // May 10
        ]
        for (i, d) in dates.enumerated() {
            let tx = Transaction(
                postedDate: d,
                rawDescription: "TX-\(i)",
                merchantNormalized: "tx-\(i)",
                amount: Money(major: Decimal(i + 1), currency: .BRL)
            )
            _ = try await txRepo.insert(
                tx, fingerprint: "fp-\(i)",
                importBatchId: batch.id!, cardId: card.id!, merchantId: nil
            )
        }

        // Bounds span April → May.
        let bounds = try await txRepo.postedDateBounds()
        XCTAssertEqual(bounds?.min, aprilStart)
        XCTAssertEqual(bounds?.max, cal.date(byAdding: .day, value: 9, to: mayStart)!)

        // April count + paging.
        let aprilCount = try await txRepo.countInMonth(start: aprilStart, endExclusive: mayStart)
        XCTAssertEqual(aprilCount, 5)

        let aprilPage1 = try await txRepo.inMonth(start: aprilStart, endExclusive: mayStart, limit: 3, offset: 0)
        let aprilPage2 = try await txRepo.inMonth(start: aprilStart, endExclusive: mayStart, limit: 3, offset: 3)
        XCTAssertEqual(aprilPage1.count, 3)
        XCTAssertEqual(aprilPage2.count, 2)

        // Newest-first ordering: page 1 starts at Apr 30.
        XCTAssertEqual(aprilPage1.first?.postedDate, cal.date(byAdding: .day, value: 29, to: aprilStart))
        // Pages don't overlap.
        let page1Ids = Set(aprilPage1.compactMap(\.id))
        let page2Ids = Set(aprilPage2.compactMap(\.id))
        XCTAssertTrue(page1Ids.isDisjoint(with: page2Ids))

        // May filter excludes April rows.
        let mayCount = try await txRepo.countInMonth(start: mayStart, endExclusive: juneStart)
        XCTAssertEqual(mayCount, 3)
    }

    func testPostedDateBounds_EmptyTable() async throws {
        let store = try makeStore()
        let txRepo = TransactionRepository(store: store)
        let bounds = try await txRepo.postedDateBounds()
        XCTAssertNil(bounds)
    }

    func testImportBatchSha256IsUnique() async throws {
        let store = try makeStore()
        let batchRepo = ImportBatchRepository(store: store)
        let mk = { (sha: String) in
            ImportBatch(
                sourceFileName: "x.pdf",
                sourceFileSha256: sha,
                sourcePages: 1,
                statementTotal: Money(major: 0, currency: .BRL),
                llmProvider: .mock,
                llmModel: "m",
                llmPromptVersion: "v1",
                llmInputTokens: 0, llmOutputTokens: 0, llmCostUSD: 0,
                validationStatus: .ok
            )
        }
        _ = try await batchRepo.insert(mk("dup"))
        do {
            _ = try await batchRepo.insert(mk("dup"))
            XCTFail("expected unique-constraint failure on sha256")
        } catch {
            // expected
        }
    }
}
