import XCTest
@testable import Categorization

final class CategorizationTests: XCTestCase {
    func testPlaceholderIsWired() {
        XCTAssertEqual(Categorization.placeholder, "PocketLens.Categorization")
    }
}
