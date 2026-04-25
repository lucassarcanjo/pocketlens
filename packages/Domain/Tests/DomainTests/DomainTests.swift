import XCTest
@testable import Domain

final class DomainTests: XCTestCase {
    func testPlaceholderIsWired() {
        XCTAssertEqual(Domain.placeholder, "PocketLens.Domain")
    }
}
