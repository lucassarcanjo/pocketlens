import XCTest
@testable import LLM

/// Round-trip test against the real macOS Keychain. Uses a unique service
/// name per run so it doesn't clash with any real PocketLens key on the
/// developer's machine.
final class KeychainStoreTests: XCTestCase {

    private var store: KeychainStore!

    override func setUp() {
        super.setUp()
        let unique = "pocketlens.tests.\(UUID().uuidString)"
        store = KeychainStore(service: unique)
    }

    override func tearDown() {
        try? store.delete()
        store = nil
        super.tearDown()
    }

    func testReadOnEmpty_ReturnsNil() throws {
        XCTAssertNil(try store.read())
    }

    func testWriteThenRead() throws {
        try store.write("sk-test-abcdef")
        XCTAssertEqual(try store.read(), "sk-test-abcdef")
    }

    func testWriteOverwrites() throws {
        try store.write("first")
        try store.write("second")
        XCTAssertEqual(try store.read(), "second")
    }

    func testDelete_RemovesEntry() throws {
        try store.write("x")
        try store.delete()
        XCTAssertNil(try store.read())
    }

    func testDeleteOnEmpty_DoesNotThrow() {
        // Should be safely idempotent — Settings deletes on user "Forget key"
        // and we don't want to error if there wasn't one.
        XCTAssertNoThrow(try store.delete())
    }
}
