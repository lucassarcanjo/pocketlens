import XCTest
@testable import LLM

/// Snapshot-style guards on the prompt constants. Keep these strict — the
/// version bump is the canary that tells us historical batches may not
/// reproduce identically.
final class ExtractionPromptV1Tests: XCTestCase {

    func testVersionPinned() {
        XCTAssertEqual(ExtractionPromptV1.version, "v1")
    }

    func testToolName() {
        XCTAssertEqual(ExtractionPromptV1.toolName, "record_extracted_statement")
    }

    func testSystemPromptCoversCriticalRules() {
        let p = ExtractionPromptV1.systemPrompt
        // The non-negotiable rules. If any of these vanish from the prompt
        // we want a loud test failure, not silent extraction drift.
        XCTAssertTrue(p.contains("forecast"),                "must mention forecast section exclusion")
        XCTAssertTrue(p.contains("Compras parceladas"),      "must name the forecast section literally")
        XCTAssertTrue(p.contains("posted_year_inferred"),    "must mention year inference")
        XCTAssertTrue(p.contains("installment_current"),     "must specify installment encoding")
        XCTAssertTrue(p.contains("Repasse de IOF"),          "must call out IOF as its own row")
        XCTAssertTrue(p.contains("virtual_card"),            "must define purchase_method tokens")
        XCTAssertTrue(p.contains("digital_wallet"),          "must define purchase_method tokens")
    }

    func testToolSchemaIsValidJSON() throws {
        let data = ExtractionPromptV1.toolSchemaJSON.data(using: .utf8)!
        let any = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(any is [String: Any])
    }

    func testToolSchemaDeclaresRequiredTopLevelKeys() throws {
        let data = ExtractionPromptV1.toolSchemaJSON.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let required = dict["required"] as? [String] ?? []
        XCTAssertEqual(
            Set(required),
            Set(["statement", "cards", "transactions", "warnings"])
        )
    }
}
