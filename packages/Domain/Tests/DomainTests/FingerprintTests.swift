import XCTest
@testable import Domain

final class FingerprintTests: XCTestCase {

    private func makeTx(
        date: String = "2026-03-15",
        merchant: String = "uber trip",
        minor: Int = 2_550,
        currency: Currency = .BRL,
        installment: Installment? = nil,
        method: PurchaseMethod = .physical
    ) -> Transaction {
        let d = Self.parseDate(date)
        return Transaction(
            postedDate: d,
            rawDescription: "UBER *TRIP",
            merchantNormalized: merchant,
            amount: Money(minorUnits: minor, currency: currency),
            installment: installment,
            purchaseMethod: method
        )
    }

    private static func parseDate(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)!
    }

    func testFingerprint_IsStable() {
        let tx = makeTx()
        let fp1 = tx.fingerprint(cardLast4: "1111")
        let fp2 = tx.fingerprint(cardLast4: "1111")
        XCTAssertEqual(fp1, fp2)
    }

    func testFingerprint_IsHexSHA1Length() {
        // SHA-1 → 20 bytes → 40 hex chars.
        let fp = makeTx().fingerprint(cardLast4: "1111")
        XCTAssertEqual(fp.count, 40)
        XCTAssertTrue(fp.allSatisfy { $0.isHexDigit })
    }

    func testFingerprint_DifferentCards_DifferentDigest() {
        let tx = makeTx()
        XCTAssertNotEqual(
            tx.fingerprint(cardLast4: "1111"),
            tx.fingerprint(cardLast4: "2222")
        )
    }

    func testFingerprint_DifferentInstallments_DifferentDigest() {
        // Two purchase rows with the same merchant/date/amount/card but
        // different installment numbers must NOT collide. This is the
        // "two simultaneous parcelas" edge case from the dedup tests.
        let a = makeTx(installment: Installment(current: 1, total: 10))
        let b = makeTx(installment: Installment(current: 2, total: 10))
        XCTAssertNotEqual(
            a.fingerprint(cardLast4: "1111"),
            b.fingerprint(cardLast4: "1111")
        )
    }

    func testFingerprint_SameRowAgain_Collides() {
        // Two rows that ARE genuine duplicates must collide. This is what
        // the unique constraint on `transactions.fingerprint` enforces.
        let a = makeTx()
        let b = makeTx()
        XCTAssertEqual(
            a.fingerprint(cardLast4: "1111"),
            b.fingerprint(cardLast4: "1111")
        )
    }

    func testFingerprint_DifferentPurchaseMethod_DifferentDigest() {
        // Same line on physical vs virtual card → still distinct rows.
        let phys = makeTx(method: .physical)
        let virt = makeTx(method: .virtualCard)
        XCTAssertNotEqual(
            phys.fingerprint(cardLast4: "1111"),
            virt.fingerprint(cardLast4: "1111")
        )
    }
}
