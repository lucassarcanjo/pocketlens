import XCTest
@testable import LLM

final class RedactorTests: XCTestCase {
    private let redactor = Redactor()

    func testStripsCardNumber_KeepsLast4() {
        let input  = "Cartão 5500 6600 7700 1111 JOHN A DOE"
        let output = redactor.redact(input)
        XCTAssertFalse(output.contains("5500 6600 7700"))
        XCTAssertFalse(output.contains("5500.6600.7700"))
        XCTAssertTrue(output.contains("1111"))
    }

    func testStripsCPF() {
        let s = redactor.redact("CPF 123.456.789-00 cadastrado")
        XCTAssertFalse(s.contains("123.456.789-00"))
        XCTAssertTrue(s.contains("[CPF]"))
    }

    func testStripsCNPJ() {
        let s = redactor.redact("CNPJ 12.345.678/0001-90")
        XCTAssertFalse(s.contains("12.345.678/0001-90"))
        XCTAssertTrue(s.contains("[CNPJ]"))
    }

    func testStripsAddressLine_PreservesCity() {
        // Itaú prints address followed by city/state. We strip the street
        // line and want the city below to survive — categorization needs it.
        let input = """
        Endereço: Rua Tomás Gonzaga, 120
        BELO HORIZONTE / MG  30180-140
        """
        let output = redactor.redact(input)
        XCTAssertFalse(output.contains("Rua Tomás Gonzaga"))
        XCTAssertTrue(output.contains("[ADDRESS]"))
        XCTAssertTrue(output.contains("BELO HORIZONTE"))
        XCTAssertTrue(output.contains("MG"))
    }

    func testPreservesMerchantText() {
        // Things that look numeric but aren't card-shaped should pass through.
        let s = redactor.redact("UBER *TRIP   2025-10-02   R$ 25,50")
        XCTAssertTrue(s.contains("UBER *TRIP"))
        XCTAssertTrue(s.contains("R$ 25,50"))
    }

    func testRulesArePluggable() {
        let extra = Redactor.Rule(
            name: "phone-br",
            pattern: #"\b\(?\d{2}\)?\s?9?\d{4}-\d{4}\b"#,
            replacement: "[PHONE]"
        )
        let r = Redactor(rules: Redactor.defaultRules + [extra])
        let s = r.redact("Contato (31) 99999-1234")
        XCTAssertTrue(s.contains("[PHONE]"))
        XCTAssertFalse(s.contains("99999-1234"))
    }

    func testMultipleRulesInOneInput() {
        let input = """
        Cartão 5555 1234 5678 9012 — titular CPF 111.222.333-44
        Endereço: Av. Paulista, 1000
        SAO PAULO / SP
        """
        let s = redactor.redact(input)
        XCTAssertTrue(s.contains("XXXX.XXXX.XXXX.9012"))
        XCTAssertTrue(s.contains("[CPF]"))
        XCTAssertTrue(s.contains("[ADDRESS]"))
        XCTAssertTrue(s.contains("SAO PAULO"))
    }
}
