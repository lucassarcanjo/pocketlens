import XCTest
@testable import LLM

final class LLMTests: XCTestCase {
    func testPlaceholderIsWired() {
        XCTAssertEqual(LLM.placeholder, "PocketLens.LLM")
    }
}
