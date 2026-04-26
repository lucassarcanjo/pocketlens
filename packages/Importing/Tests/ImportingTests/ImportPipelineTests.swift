import XCTest
@testable import Importing
import Domain
import LLM

/// End-to-end pipeline test driven by `MockLLMProvider`.
///
/// This is the centerpiece test from the plan's "Test Coverage" section:
/// fixture → mock LLM → pipeline → expected transaction count + totals,
/// installment parsing, international + IOF, multi-card grouping.
final class ImportPipelineTests: XCTestCase {

    func testFixture_ProducesPlanWithExpectedShape() async throws {
        let dto = try loadFixture()
        let mock = MockLLMProvider(canned: dto, model: "mock-1")
        let pipeline = ImportPipeline(provider: mock)

        // Drive the pipeline via `makePlan` so we don't need a real PDF on
        // disk — the goal is to assert on the plan, not on PDFKit.
        let extraction = try await mock.extractStatement(text: "ignored", hints: ExtractionHints())
        let report = ExtractionValidator().validate(extraction.statement)
        let plan = pipeline.makePlan(
            extraction: extraction,
            report: report,
            sha256: "deadbeef",
            sourceFileName: "itau-personnalite-2026-03.pdf",
            sourcePages: 5
        )

        XCTAssertEqual(plan.cards.count, 3)
        XCTAssertEqual(Set(plan.cards.map(\.last4)), ["1111", "2222", "3333"])
        XCTAssertEqual(plan.transactions.count, 9)
        XCTAssertEqual(plan.batch.validationStatus, .ok)
        XCTAssertEqual(plan.batch.llmProvider, .mock)
        XCTAssertEqual(plan.batch.llmPromptVersion, ExtractionPromptV1.version)
        XCTAssertEqual(plan.batch.sourceFileSha256, "deadbeef")
        XCTAssertEqual(plan.batch.sourcePages, 5)
        XCTAssertEqual(plan.batch.statementTotal.minorUnits, 1_626_506)
    }

    func testFixture_GroupsTransactionsByCardCorrectly() async throws {
        let plan = try await runFixturePipeline()
        let counts = Dictionary(grouping: plan.transactions, by: \.cardLast4)
            .mapValues(\.count)
        XCTAssertEqual(counts["1111"], 4)
        XCTAssertEqual(counts["2222"], 3)
        XCTAssertEqual(counts["3333"], 2)
    }

    func testFixture_ParsesInstallments() async throws {
        let plan = try await runFixturePipeline()
        let vivara = plan.transactions.first { $0.transaction.rawDescription.contains("VIVARA") }
        XCTAssertNotNil(vivara)
        XCTAssertEqual(vivara?.transaction.installment, Installment(current: 6, total: 10))
        XCTAssertEqual(vivara?.transaction.amount.minorUnits, 73_858)
        XCTAssertEqual(vivara?.merchantNormalized, "vivara bbh")
    }

    func testFixture_ParsesInternationalAndIOF() async throws {
        let plan = try await runFixturePipeline()
        let amazon = plan.transactions.first { $0.merchantNormalized == "amazon us" }
        XCTAssertEqual(amazon?.transaction.amount.currency, .BRL)
        XCTAssertEqual(amazon?.transaction.originalAmount?.currency, .USD)
        XCTAssertEqual(amazon?.transaction.fxRate, Decimal(string: "5.054"))

        let iof = plan.transactions.first { $0.transaction.transactionType == .iof }
        XCTAssertNotNil(iof, "IOF row must be preserved as its own transaction")
        XCTAssertEqual(iof?.transaction.amount.minorUnits, 1_134)
    }

    func testFixture_PurchaseMethodGlyphsHonored() async throws {
        let plan = try await runFixturePipeline()
        // `@ NETFLIX.COM` → virtual_card.
        let netflix = plan.transactions.first { $0.merchantNormalized == "netflix.com" }
        XCTAssertEqual(netflix?.transaction.purchaseMethod, .virtualCard)
    }

    func testFingerprintsAreUniqueWithinFixture() async throws {
        let plan = try await runFixturePipeline()
        let fingerprints = plan.transactions.map(\.fingerprint)
        XCTAssertEqual(Set(fingerprints).count, fingerprints.count, "fingerprints must be unique")
    }

    func testDuplicateFixture_CollapsesAndWarns() async throws {
        // Same statement text, but emit each transaction twice — pipeline
        // should dedup back to the original count and surface a warning.
        var dto = try loadFixture()
        dto.transactions = dto.transactions + dto.transactions
        // The validator will fail (sums double) but dedup runs first on the
        // pipeline's plan-building side. We test dedup specifically by
        // checking the unique count and the warning.
        let mock = MockLLMProvider(canned: dto)
        let extraction = try await mock.extractStatement(text: "", hints: ExtractionHints())
        let report = ExtractionValidator().validate(extraction.statement)
        let pipeline = ImportPipeline(provider: mock)
        let plan = pipeline.makePlan(
            extraction: extraction,
            report: report,
            sha256: "x",
            sourceFileName: "x.pdf",
            sourcePages: 1
        )
        XCTAssertEqual(plan.transactions.count, 9)
        XCTAssertTrue(plan.batch.parseWarnings.contains { $0.contains("Collapsed 9 duplicate") })
    }

    // MARK: - Helpers

    private func loadFixture() throws -> ExtractedStatement {
        let url = Bundle.module.url(
            forResource: "itau-personnalite-2026-03",
            withExtension: "json",
            subdirectory: "Fixtures"
        )!
        let data = try Data(contentsOf: url)
        return try ExtractedStatement.makeJSONDecoder().decode(
            ExtractedStatement.self, from: data
        )
    }

    private func runFixturePipeline() async throws -> ImportPlan {
        let dto = try loadFixture()
        let mock = MockLLMProvider(canned: dto)
        let pipeline = ImportPipeline(provider: mock)
        let extraction = try await mock.extractStatement(text: "", hints: ExtractionHints())
        let report = ExtractionValidator().validate(extraction.statement)
        return pipeline.makePlan(
            extraction: extraction,
            report: report,
            sha256: "x",
            sourceFileName: "x.pdf",
            sourcePages: 5
        )
    }
}
