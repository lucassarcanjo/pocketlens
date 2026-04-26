import XCTest
@testable import Categorization

final class CategorizationTests: XCTestCase {
    func testPhaseConstantIsCurrent() {
        XCTAssertEqual(Categorization.phase, "v0.2")
    }
}
