import XCTest
@testable import Persistence

final class PersistenceTests: XCTestCase {
    func testPlaceholderIsWired() {
        XCTAssertEqual(Persistence.placeholder, "PocketLens.Persistence")
    }
}
