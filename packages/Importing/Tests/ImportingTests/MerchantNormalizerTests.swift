import XCTest
@testable import Importing

final class MerchantNormalizerTests: XCTestCase {

    func testCasefoldsAndCollapsesWhitespace() {
        XCTAssertEqual(
            MerchantNormalizer.normalize("  UBER   *TRIP  SP   "),
            "uber *trip sp"
        )
    }

    func testStripsTrailingInstallmentMarker() {
        XCTAssertEqual(MerchantNormalizer.normalize("VIVARA BBH 06/10"), "vivara bbh")
        XCTAssertEqual(MerchantNormalizer.normalize("Casas Bahia 1/12"),  "casas bahia")
    }

    func testStripsLeadingProviderPrefix() {
        XCTAssertEqual(MerchantNormalizer.normalize("MP *Padaria"),    "padaria")
        XCTAssertEqual(MerchantNormalizer.normalize("IFD*RestauranteX"), "restaurantex")
        XCTAssertEqual(MerchantNormalizer.normalize("PIX * fulano"),   "fulano")
    }

    func testCombinesAllSteps() {
        XCTAssertEqual(
            MerchantNormalizer.normalize("  IFD*  Padaria Real  06/12 "),
            "padaria real"
        )
    }

    func testIdempotent() {
        let once = MerchantNormalizer.normalize("UBER *TRIP 06/10")
        let twice = MerchantNormalizer.normalize(once)
        XCTAssertEqual(once, twice)
    }
}
