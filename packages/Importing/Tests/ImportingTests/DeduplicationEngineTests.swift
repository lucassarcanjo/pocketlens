import XCTest
@testable import Importing
import Domain

final class DeduplicationEngineTests: XCTestCase {

    func testCollapsesSameFingerprint_KeepsFirst() {
        let dedup = DeduplicationEngine()
        let a = makePending(fingerprint: "fp1", merchant: "first")
        let b = makePending(fingerprint: "fp1", merchant: "second")
        let c = makePending(fingerprint: "fp2", merchant: "third")

        let result = dedup.collapse([a, b, c])
        XCTAssertEqual(result.unique.count, 2)
        XCTAssertEqual(result.collapsed, 1)
        // Order-stable, first wins.
        XCTAssertEqual(result.unique[0].merchantNormalized, "first")
        XCTAssertEqual(result.unique[1].merchantNormalized, "third")
    }

    func testEmptyInput() {
        let dedup = DeduplicationEngine()
        let result = dedup.collapse([])
        XCTAssertTrue(result.unique.isEmpty)
        XCTAssertEqual(result.collapsed, 0)
    }

    private func makePending(fingerprint: String, merchant: String) -> PendingTransaction {
        PendingTransaction(
            cardLast4: "0001",
            merchantNormalized: merchant,
            transaction: Transaction(
                postedDate: Date(timeIntervalSince1970: 0),
                rawDescription: merchant,
                merchantNormalized: merchant,
                amount: Money(minorUnits: 100, currency: .BRL)
            ),
            fingerprint: fingerprint
        )
    }
}
