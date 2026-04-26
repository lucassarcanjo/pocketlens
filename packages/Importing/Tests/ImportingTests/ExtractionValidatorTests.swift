import XCTest
@testable import Importing
import Domain
import LLM

final class ExtractionValidatorTests: XCTestCase {

    private let validator = ExtractionValidator()

    func testValidStatement_PassesWithOK() {
        let s = ExtractedStatement(
            statement: .init(
                issuer: "Mock",
                currency: .BRL,
                totals: .init(currentChargesTotal: Decimal(string: "300.00")!)
            ),
            cards: [
                .init(last4: "0001", holderName: "A", subtotal: Decimal(string: "300.00")!),
            ],
            transactions: [
                makeTx(card: "0001", amount: "100.00"),
                makeTx(card: "0001", amount: "200.00"),
            ],
            warnings: []
        )
        let r = validator.validate(s)
        XCTAssertEqual(r.status, .ok)
        XCTAssertTrue(r.warnings.isEmpty)
    }

    func testCardSubtotalMismatch_Fails() {
        let s = ExtractedStatement(
            statement: .init(
                issuer: "Mock",
                currency: .BRL,
                totals: .init(currentChargesTotal: Decimal(string: "300.00")!)
            ),
            cards: [
                .init(last4: "0001", holderName: "A", subtotal: Decimal(string: "350.00")!),
            ],
            transactions: [
                makeTx(card: "0001", amount: "100.00"),
                makeTx(card: "0001", amount: "200.00"),
            ]
        )
        let r = validator.validate(s)
        XCTAssertEqual(r.status, .failed)
        XCTAssertTrue(r.warnings.contains { $0.contains("Card 0001") })
    }

    func testGrandTotalMismatch_Fails() {
        let s = ExtractedStatement(
            statement: .init(
                issuer: "Mock",
                currency: .BRL,
                totals: .init(currentChargesTotal: Decimal(string: "999.00")!)
            ),
            cards: [
                .init(last4: "0001", holderName: "A", subtotal: Decimal(string: "300.00")!),
            ],
            transactions: [
                makeTx(card: "0001", amount: "100.00"),
                makeTx(card: "0001", amount: "200.00"),
            ]
        )
        let r = validator.validate(s)
        XCTAssertEqual(r.status, .failed)
        XCTAssertTrue(r.warnings.contains { $0.contains("Grand total") })
    }

    func testCentavoTolerance_DoesNotFail() {
        // Exactly R$0.01 of error should be tolerated.
        let s = ExtractedStatement(
            statement: .init(
                issuer: "Mock",
                currency: .BRL,
                totals: .init(currentChargesTotal: Decimal(string: "300.01")!)
            ),
            cards: [
                .init(last4: "0001", holderName: "A", subtotal: Decimal(string: "300.00")!),
            ],
            transactions: [
                makeTx(card: "0001", amount: "100.00"),
                makeTx(card: "0001", amount: "200.00"),
            ]
        )
        let r = validator.validate(s)
        XCTAssertEqual(r.status, .ok)
    }

    func testOrphanCardRef_Fails() {
        let s = ExtractedStatement(
            statement: .init(
                issuer: "Mock",
                currency: .BRL,
                totals: .init(currentChargesTotal: Decimal(string: "100.00")!)
            ),
            cards: [
                .init(last4: "0001", holderName: "A", subtotal: Decimal(string: "100.00")!),
            ],
            transactions: [
                makeTx(card: "9999", amount: "100.00"),
            ]
        )
        let r = validator.validate(s)
        XCTAssertEqual(r.status, .failed)
        XCTAssertTrue(r.warnings.contains { $0.contains("9999") })
    }

    func testLowConfidenceFraction_Warns() {
        var rows: [ExtractedStatement.TransactionRow] = []
        // 50 high-confidence rows + 5 low — 9.1% > 2% threshold.
        for _ in 0..<50 { rows.append(makeTx(card: "0001", amount: "1.00", confidence: 0.99)) }
        for _ in 0..<5  { rows.append(makeTx(card: "0001", amount: "1.00", confidence: 0.5))  }
        let total = Decimal(55)
        let s = ExtractedStatement(
            statement: .init(
                issuer: "Mock",
                currency: .BRL,
                totals: .init(currentChargesTotal: total)
            ),
            cards: [
                .init(last4: "0001", holderName: "A", subtotal: total),
            ],
            transactions: rows
        )
        let r = validator.validate(s)
        XCTAssertEqual(r.status, .warning)
        XCTAssertTrue(r.warnings.contains { $0.contains("Low-confidence") })
    }

    func testFixturePassesValidation() throws {
        let s = try loadFixture()
        let r = validator.validate(s)
        XCTAssertEqual(r.status, .ok, "fixture warnings: \(r.warnings)")
    }

    // MARK: - Helpers

    private func makeTx(
        card: String,
        amount: String,
        confidence: Double = 0.99
    ) -> ExtractedStatement.TransactionRow {
        ExtractedStatement.TransactionRow(
            cardLast4: card,
            postedDate: Date(timeIntervalSince1970: 0),
            postedYearInferred: false,
            rawDescription: "X",
            merchant: "X",
            amount: Decimal(string: amount)!,
            currency: .BRL,
            purchaseMethod: .physical,
            transactionType: .purchase,
            confidence: confidence
        )
    }

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
}
