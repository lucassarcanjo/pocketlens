import XCTest
@testable import PocketLens

final class PocketLensTests: XCTestCase {
    func testAppBundleLoads() {
        // Sanity check that the app target's test bundle wiring works end-to-end.
        // Real tests for view models, importers, and flows land in the relevant
        // SPM package test targets. This test target exists primarily to host
        // UI / integration tests that need the full app bundle.
        XCTAssertTrue(true)
    }
}
