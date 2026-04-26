import XCTest
@testable import LLM
import Domain

final class MockLLMProviderTests: XCTestCase {

    func testLoadsCannedJSONResource_AndReturnsItOnExtract() async throws {
        let url = Bundle.module.url(
            forResource: "itau-personnalite-2026-03",
            withExtension: "json",
            subdirectory: "Fixtures"
        )
        XCTAssertNotNil(url, "fixture must be copied into the test bundle")

        // The Fixtures dir is copied wholesale, so the resource lookup is via
        // the test bundle's `module` accessor. `MockLLMProvider(jsonResource:)`
        // expects a flat lookup, so use direct decoding here for the bundled
        // resource and pass it to the canned-DTO initializer.
        let data = try Data(contentsOf: url!)
        let dto = try ExtractedStatement.makeJSONDecoder().decode(
            ExtractedStatement.self, from: data
        )
        let provider = MockLLMProvider(canned: dto)

        XCTAssertEqual(provider.kind, .mock)
        XCTAssertEqual(provider.promptVersion, ExtractionPromptV1.version)

        let result = try await provider.extractStatement(
            text: "irrelevant for mock",
            hints: ExtractionHints()
        )
        XCTAssertEqual(result.statement.transactions.count, 9)
        XCTAssertEqual(result.promptVersion, ExtractionPromptV1.version)
        XCTAssertEqual(result.costUSD, 0)
    }

    func testCannedInit_ReturnsThatExactStatement() async throws {
        let dto = ExtractedStatement(
            statement: .init(
                issuer: "Mock Bank",
                currency: .BRL,
                totals: .init(currentChargesTotal: 0)
            ),
            cards: [],
            transactions: [],
            warnings: []
        )
        let provider = MockLLMProvider(canned: dto)
        let result = try await provider.extractStatement(text: "", hints: ExtractionHints())
        XCTAssertEqual(result.statement, dto)
    }
}
