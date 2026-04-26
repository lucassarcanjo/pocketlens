import XCTest
@testable import LLM
import Domain

final class ExtractedStatementCodableTests: XCTestCase {

    func testRoundTrip() throws {
        let original = ExtractedStatement(
            statement: .init(
                issuer: "Itaú Personnalité",
                product: "Mastercard Black",
                periodStart: makeDate("2026-03-01"),
                periodEnd: makeDate("2026-03-30"),
                dueDate: makeDate("2026-04-06"),
                currency: .BRL,
                totals: .init(currentChargesTotal: Decimal(string: "16265.06")!)
            ),
            cards: [
                .init(last4: "1111", holderName: "JOHN", subtotal: Decimal(string: "7473.18")!),
            ],
            transactions: [
                .init(
                    cardLast4: "1111",
                    postedDate: makeDate("2025-10-02"),
                    postedYearInferred: true,
                    rawDescription: "VIVARA BBH 06/10",
                    merchant: "VIVARA BBH",
                    merchantCity: "BELO HORIZONTE",
                    bankCategoryRaw: "DIVERSOS",
                    amount: Decimal(string: "738.58")!,
                    currency: .BRL,
                    installmentCurrent: 6,
                    installmentTotal: 10,
                    purchaseMethod: .physical,
                    transactionType: .purchase,
                    confidence: 0.94
                ),
            ],
            warnings: ["test"]
        )

        let encoded = try ExtractedStatement.makeJSONEncoder().encode(original)
        let decoded = try ExtractedStatement.makeJSONDecoder().decode(
            ExtractedStatement.self, from: encoded
        )
        XCTAssertEqual(decoded, original)
    }

    func testDecodesCannedFixture() throws {
        let url = try fixtureURL("itau-personnalite-2026-03")
        let data = try Data(contentsOf: url)
        let s = try ExtractedStatement.makeJSONDecoder().decode(
            ExtractedStatement.self, from: data
        )

        XCTAssertEqual(s.statement.issuer, "Itaú Personnalité")
        XCTAssertEqual(s.statement.currency, .BRL)
        XCTAssertEqual(s.cards.count, 3)
        XCTAssertEqual(s.transactions.count, 9)

        // Spot-check the international + IOF rows.
        let amazon = s.transactions.first { $0.merchant == "AMAZON US" }
        XCTAssertEqual(amazon?.originalCurrency, .USD)
        XCTAssertEqual(amazon?.fxRate, Decimal(string: "5.054"))

        let iof = s.transactions.first { $0.transactionType == .iof }
        XCTAssertEqual(iof?.amount, Decimal(string: "11.34"))

        // Spot-check the installment row.
        let vivara = s.transactions.first { $0.merchant == "VIVARA BBH" }
        XCTAssertEqual(vivara?.installmentCurrent, 6)
        XCTAssertEqual(vivara?.installmentTotal, 10)
        XCTAssertTrue(vivara?.postedYearInferred ?? false)
    }

    // MARK: - Helpers

    private func fixtureURL(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw NSError(
                domain: "LLMTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "fixture \(name).json not found"]
            )
        }
        return url
    }

    private func makeDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)!
    }
}
