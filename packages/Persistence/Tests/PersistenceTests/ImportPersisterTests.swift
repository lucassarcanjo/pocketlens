import XCTest
@testable import Persistence
import Domain
import Importing
import LLM

final class ImportPersisterTests: XCTestCase {

    func testEndToEnd_PersistsPlanInOneTransaction() async throws {
        let store = try SQLiteStore.makeInMemory()
        try DefaultDataSeeder.seed(into: store)
        let plan = try await makeFixturePlan()

        let persister = ImportPersister(store: store)
        let result = try await persister.persist(
            plan: plan,
            bankName: "Itaú Personnalité"
        )

        XCTAssertEqual(result.transactionCount, 9)
        XCTAssertEqual(result.cardCount, 3)
        XCTAssertNotNil(result.batch.id)

        // Verify rows landed.
        let txs = try await TransactionRepository(store: store).all()
        XCTAssertEqual(txs.count, 9)
        let batches = try await ImportBatchRepository(store: store).all()
        XCTAssertEqual(batches.count, 1)
        let cards = try await CardRepository(store: store).all()
        XCTAssertEqual(cards.count, 3)
    }

    func testRejectsDuplicateFile() async throws {
        let store = try SQLiteStore.makeInMemory()
        let plan = try await makeFixturePlan()
        let persister = ImportPersister(store: store)
        _ = try await persister.persist(plan: plan, bankName: "Itaú")

        do {
            _ = try await persister.persist(plan: plan, bankName: "Itaú")
            XCTFail("expected alreadyImported")
        } catch let ImportPersister.Error.alreadyImported(batch) {
            XCTAssertNotNil(batch.id)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testTransactionFingerprintUniqueness_RejectsCrossBatchDuplicate() async throws {
        // Two distinct files (different SHA-256), same transactions inside —
        // the fingerprint UNIQUE on the transactions table prevents a single
        // duplicate row landing twice. Whole second batch fails atomically.
        let store = try SQLiteStore.makeInMemory()
        var plan1 = try await makeFixturePlan()
        plan1.batch = batchSwapping(sha: "aaa", from: plan1.batch)
        var plan2 = try await makeFixturePlan()
        plan2.batch = batchSwapping(sha: "bbb", from: plan2.batch)

        let persister = ImportPersister(store: store)
        _ = try await persister.persist(plan: plan1, bankName: "Itaú")
        do {
            _ = try await persister.persist(plan: plan2, bankName: "Itaú")
            XCTFail("expected unique fingerprint failure")
        } catch {
            // Expected — DB constraint blocks the duplicate row.
        }
        // First batch's transactions must still be intact (atomic write).
        let count = try await TransactionRepository(store: store).all().count
        XCTAssertEqual(count, 9, "first batch must remain after second's rollback")
    }

    // MARK: - Helpers

    private func makeFixturePlan() async throws -> ImportPlan {
        let dto = try loadFixture()
        let mock = MockLLMProvider(canned: dto)
        let extraction = try await mock.extractStatement(text: "", hints: ExtractionHints())
        let report = ExtractionValidator().validate(extraction.statement)
        let pipeline = ImportPipeline(provider: mock)
        return pipeline.makePlan(
            extraction: extraction,
            report: report,
            sha256: "fixturesha",
            sourceFileName: "itau-personnalite.pdf",
            sourcePages: 5
        )
    }

    private func loadFixture() throws -> ExtractedStatement {
        // Test bundle for Persistence doesn't have the fixture — build the
        // DTO inline. Mirrors the LLMTests fixture.
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        let day = { f.date(from: $0)! }
        return ExtractedStatement(
            statement: .init(
                issuer: "Itaú Personnalité",
                product: "Mastercard Black",
                periodStart: day("2026-03-01"),
                periodEnd: day("2026-03-30"),
                dueDate: day("2026-04-06"),
                currency: .BRL,
                totals: .init(
                    previousBalance: 0, paymentReceived: 0, revolvingBalance: 0,
                    currentChargesTotal: Decimal(string: "16265.06")!
                )
            ),
            cards: [
                .init(last4: "1111", holderName: "JOHN A DOE", network: "Mastercard", tier: "Black", subtotal: Decimal(string: "7473.18")!),
                .init(last4: "2222", holderName: "JOHN A DOE", network: "Mastercard", tier: "Black", subtotal: Decimal(string: "4542.90")!),
                .init(last4: "3333", holderName: "JANE B SMITH", network: "Mastercard", tier: "Black", subtotal: Decimal(string: "4248.98")!),
            ],
            transactions: [
                .init(cardLast4: "1111", postedDate: day("2026-03-12"), postedYearInferred: true, rawDescription: "PADARIA REAL", merchant: "PADARIA REAL", merchantCity: "BELO HORIZONTE", bankCategoryRaw: "ALIMENTAÇÃO", amount: Decimal(string: "87.40")!, currency: .BRL, purchaseMethod: .physical, transactionType: .purchase, confidence: 0.98),
                .init(cardLast4: "1111", postedDate: day("2025-10-02"), postedYearInferred: true, rawDescription: "VIVARA BBH 06/10", merchant: "VIVARA BBH", merchantCity: "BELO HORIZONTE", bankCategoryRaw: "DIVERSOS", amount: Decimal(string: "738.58")!, currency: .BRL, installmentCurrent: 6, installmentTotal: 10, purchaseMethod: .physical, transactionType: .purchase, confidence: 0.94),
                .init(cardLast4: "1111", postedDate: day("2026-03-20"), postedYearInferred: true, rawDescription: "@ NETFLIX.COM", merchant: "NETFLIX.COM", merchantCity: "SAO PAULO", bankCategoryRaw: "ASSINATURAS", amount: Decimal(string: "55.90")!, currency: .BRL, purchaseMethod: .virtualCard, transactionType: .purchase, confidence: 0.99),
                .init(cardLast4: "1111", postedDate: day("2026-03-22"), postedYearInferred: true, rawDescription: "POSTO IPIRANGA", merchant: "POSTO IPIRANGA", merchantCity: "BELO HORIZONTE", bankCategoryRaw: "TRANSPORTE", amount: Decimal(string: "6591.30")!, currency: .BRL, purchaseMethod: .physical, transactionType: .purchase, confidence: 0.99),
                .init(cardLast4: "2222", postedDate: day("2026-03-05"), postedYearInferred: true, rawDescription: "MERCADO MUNICIPAL", merchant: "MERCADO MUNICIPAL", merchantCity: "BELO HORIZONTE", bankCategoryRaw: "ALIMENTAÇÃO", amount: Decimal(string: "4208.11")!, currency: .BRL, purchaseMethod: .physical, transactionType: .purchase, confidence: 0.98),
                .init(cardLast4: "2222", postedDate: day("2026-03-18"), postedYearInferred: true, rawDescription: "AMAZON US", merchant: "AMAZON US", merchantCity: "SEATTLE", bankCategoryRaw: "VAREJO", amount: Decimal(string: "323.45")!, currency: .BRL, originalAmount: Decimal(string: "64.00")!, originalCurrency: .USD, fxRate: Decimal(string: "5.054")!, purchaseMethod: .virtualCard, transactionType: .purchase, confidence: 0.93),
                .init(cardLast4: "2222", postedDate: day("2026-03-18"), postedYearInferred: true, rawDescription: "REPASSE DE IOF", merchant: "REPASSE DE IOF", amount: Decimal(string: "11.34")!, currency: .BRL, purchaseMethod: .unknown, transactionType: .iof, confidence: 1.0),
                .init(cardLast4: "3333", postedDate: day("2026-03-08"), postedYearInferred: true, rawDescription: "FARMACIA PACHECO", merchant: "FARMACIA PACHECO", merchantCity: "BELO HORIZONTE", bankCategoryRaw: "SAÚDE", amount: Decimal(string: "1248.98")!, currency: .BRL, purchaseMethod: .physical, transactionType: .purchase, confidence: 0.97),
                .init(cardLast4: "3333", postedDate: day("2026-03-15"), postedYearInferred: true, rawDescription: "ZARA", merchant: "ZARA", merchantCity: "BELO HORIZONTE", bankCategoryRaw: "VESTUÁRIO", amount: Decimal(string: "3000.00")!, currency: .BRL, purchaseMethod: .physical, transactionType: .purchase, confidence: 0.99),
            ],
            warnings: []
        )
    }

    private func batchSwapping(sha: String, from b: ImportBatch) -> ImportBatch {
        var copy = b
        copy.sourceFileSha256 = sha
        copy.sourceFileName = "swapped-\(sha).pdf"
        return copy
    }
}
