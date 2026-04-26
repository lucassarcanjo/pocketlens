import XCTest
@testable import Domain

final class MoneyTests: XCTestCase {

    func testInitFromMajor_RoundsToFractionDigits() {
        // BRL has 2 fraction digits → 7473.18 → 747318 minor units.
        let m = Money(major: Decimal(string: "7473.18")!, currency: .BRL)
        XCTAssertEqual(m.minorUnits, 747_318)
        XCTAssertEqual(m.currency, .BRL)
    }

    func testInitFromMajor_RoundsBankerHalfToEven() {
        // 0.005 → halfway between 0.00 and 0.01 → bankers rounds to 0.00.
        let halfDown = Money(major: Decimal(string: "0.005")!, currency: .BRL)
        XCTAssertEqual(halfDown.minorUnits, 0)
        // 0.015 → halfway between 0.01 and 0.02 → bankers rounds to 0.02.
        let halfUp = Money(major: Decimal(string: "0.015")!, currency: .BRL)
        XCTAssertEqual(halfUp.minorUnits, 2)
    }

    func testMajorAmount_RoundTrips() {
        let m = Money(minorUnits: 747_318, currency: .BRL)
        XCTAssertEqual(m.majorAmount, Decimal(string: "7473.18"))
    }

    func testZero_AndIsNegative() {
        XCTAssertTrue(Money.zero(.BRL).isZero)
        XCTAssertTrue(Money(minorUnits: -100, currency: .BRL).isNegative)
    }

    func testNegate() {
        let m = Money(minorUnits: 250, currency: .USD).negated()
        XCTAssertEqual(m.minorUnits, -250)
        XCTAssertEqual(m.currency, .USD)
    }

    // MARK: - Arithmetic

    func testAdditionSameCurrency() throws {
        let a = Money(minorUnits: 100, currency: .BRL)
        let b = Money(minorUnits: 250, currency: .BRL)
        let sum = try a + b
        XCTAssertEqual(sum, Money(minorUnits: 350, currency: .BRL))
    }

    func testSubtractionSameCurrency() throws {
        let a = Money(minorUnits: 500, currency: .BRL)
        let b = Money(minorUnits: 200, currency: .BRL)
        XCTAssertEqual(try a - b, Money(minorUnits: 300, currency: .BRL))
    }

    func testAddition_CurrencyMismatchThrows() {
        let a = Money(minorUnits: 100, currency: .BRL)
        let b = Money(minorUnits: 100, currency: .USD)
        XCTAssertThrowsError(try a + b) { error in
            XCTAssertEqual(
                error as? Money.ArithmeticError,
                .currencyMismatch(lhs: .BRL, rhs: .USD)
            )
        }
    }

    func testSum_EmptyReturnsFallbackZero() throws {
        let total = try Money.sum([Money](), fallback: .BRL)
        XCTAssertEqual(total, Money.zero(.BRL))
    }

    func testSum_AddsMatchingCurrency() throws {
        let values = (1...5).map { Money(minorUnits: $0 * 100, currency: .BRL) }
        let total = try Money.sum(values, fallback: .BRL)
        XCTAssertEqual(total.minorUnits, 100 + 200 + 300 + 400 + 500)
    }

    func testSum_RejectsMixedCurrencies() {
        let values: [Money] = [
            Money(minorUnits: 100, currency: .BRL),
            Money(minorUnits: 100, currency: .USD),
        ]
        XCTAssertThrowsError(try Money.sum(values, fallback: .BRL))
    }

    // MARK: - Comparable

    func testComparable() {
        let a = Money(minorUnits: 100, currency: .BRL)
        let b = Money(minorUnits: 200, currency: .BRL)
        XCTAssertTrue(a < b)
        XCTAssertFalse(b < a)
    }

    // MARK: - Formatting

    func testFormatted_BR() {
        let m = Money(minorUnits: 747_318, currency: .BRL)
        // pt_BR uses "." as thousands and "," as decimal, prefixed with R$.
        let s = m.formatted(locale: Locale(identifier: "pt_BR"))
        // Don't pin the exact whitespace (NBSP vs space varies by macOS version)
        // — assert on the digits + symbol instead.
        XCTAssertTrue(s.contains("R$"), s)
        XCTAssertTrue(s.contains("7.473,18"), s)
    }
}
