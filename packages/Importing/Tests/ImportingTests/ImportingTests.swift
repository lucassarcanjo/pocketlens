import XCTest
@testable import Importing

final class ImportingTests: XCTestCase {
    func testPlaceholderIsWired() {
        XCTAssertEqual(Importing.placeholder, "PocketLens.Importing")
    }
}
