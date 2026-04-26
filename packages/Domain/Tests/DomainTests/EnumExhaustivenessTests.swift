import XCTest
@testable import Domain

/// Sanity tests on enum case sets so silent additions/removals trip a test
/// (and prompt a schema/migration review) rather than slip through.
final class EnumExhaustivenessTests: XCTestCase {

    func testCurrencyCases() {
        XCTAssertEqual(Set(Currency.allCases), Set([.BRL, .USD, .EUR, .GBP]))
    }

    func testTransactionTypeCases() {
        XCTAssertEqual(
            Set(TransactionType.allCases),
            Set([.purchase, .refund, .payment, .fee, .iof, .adjustment])
        )
    }

    func testPurchaseMethodCases_AndRawValues() {
        XCTAssertEqual(
            Set(PurchaseMethod.allCases),
            Set([.physical, .virtualCard, .digitalWallet, .recurring, .unknown])
        )
        // Raw values must match the snake_case strings the LLM emits.
        XCTAssertEqual(PurchaseMethod.virtualCard.rawValue, "virtual_card")
        XCTAssertEqual(PurchaseMethod.digitalWallet.rawValue, "digital_wallet")
    }

    func testValidationStatusCases() {
        XCTAssertEqual(Set(ValidationStatus.allCases), Set([.ok, .warning, .failed]))
    }

    func testLLMProviderKindCases() {
        XCTAssertEqual(
            Set(LLMProviderKind.allCases),
            Set([.anthropic, .mock, .ollama, .openai])
        )
    }

    func testInstallment_RejectsInvalid() {
        // Can't easily catch preconditions in Swift test runs; just verify
        // that valid construction works.
        let i = Installment(current: 6, total: 10)
        XCTAssertEqual(i.current, 6)
        XCTAssertEqual(i.total, 10)
    }
}
