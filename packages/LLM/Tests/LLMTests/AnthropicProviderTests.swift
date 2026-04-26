import XCTest
@testable import LLM
import Domain

final class AnthropicProviderTests: XCTestCase {

    // MARK: - Tool-call → ExtractedStatement decoding

    func testParsesToolUseResponse() async throws {
        let canned = makeCannedResponseJSON()
        let transport = FakeTransport(responses: [(canned, 200)])
        let provider = AnthropicProvider(apiKey: "sk-test", transport: transport)

        let result = try await provider.extractStatement(
            text: "ignored", hints: ExtractionHints()
        )
        XCTAssertEqual(result.statement.cards.count, 1)
        XCTAssertEqual(result.statement.transactions.count, 1)
        XCTAssertEqual(result.inputTokens, 1234)
        XCTAssertEqual(result.outputTokens, 567)
        XCTAssertEqual(result.cacheReadTokens, 1000)
        XCTAssertEqual(result.promptVersion, ExtractionPromptV1.version)
        // Pricing: 1234 input @ $3/M + 567 output @ $15/M + 1000 cache_read @ $0.30/M.
        // = 0.003702 + 0.008505 + 0.0003 = 0.012507
        XCTAssertEqual(result.costUSD, 0.012507, accuracy: 1e-6)
    }

    // MARK: - Error paths

    func testEmptyAPIKey_Throws() async {
        let provider = AnthropicProvider(apiKey: "", transport: FakeTransport(responses: []))
        do {
            _ = try await provider.extractStatement(text: "x", hints: ExtractionHints())
            XCTFail("expected missingAPIKey")
        } catch let error as LLMError {
            XCTAssertEqual(error, .missingAPIKey)
        } catch {
            XCTFail("expected LLMError, got \(error)")
        }
    }

    func testNon2xxAfterRetries_ThrowsNetwork() async {
        let body = #"{"error":"bad"}"#.data(using: .utf8)!
        let transport = FakeTransport(responses: Array(repeating: (body, 401), count: 5))
        let provider = AnthropicProvider(apiKey: "sk", transport: transport, maxRetries: 1)
        do {
            _ = try await provider.extractStatement(text: "x", hints: ExtractionHints())
            XCTFail("expected network error")
        } catch let error as LLMError {
            if case let .network(code, _) = error {
                XCTAssertEqual(code, 401)
            } else {
                XCTFail("expected .network, got \(error)")
            }
        } catch {
            XCTFail("expected LLMError, got \(error)")
        }
    }

    func testRetriesOn429() async throws {
        let bad = #"{"error":"rate limit"}"#.data(using: .utf8)!
        let good = makeCannedResponseJSON()
        let transport = FakeTransport(responses: [(bad, 429), (good, 200)])
        let provider = AnthropicProvider(apiKey: "sk", transport: transport, maxRetries: 3)
        let result = try await provider.extractStatement(text: "x", hints: ExtractionHints())
        XCTAssertEqual(result.statement.transactions.count, 1)
        XCTAssertEqual(transport.callCount, 2)
    }

    func testToolCallNotReturned_Throws() async {
        // Response with text-only content blocks — no tool_use.
        let body = #"""
        {
          "id":"x", "model":"m", "stop_reason":"end_turn",
          "content":[{"type":"text","text":"hi"}],
          "usage":{"input_tokens":1,"output_tokens":1}
        }
        """#.data(using: .utf8)!
        let transport = FakeTransport(responses: [(body, 200)])
        let provider = AnthropicProvider(apiKey: "sk", transport: transport, maxRetries: 1)
        do {
            _ = try await provider.extractStatement(text: "x", hints: ExtractionHints())
            XCTFail("expected toolCallNotReturned")
        } catch let error as LLMError {
            XCTAssertEqual(error, .toolCallNotReturned)
        } catch {
            XCTFail("got \(error)")
        }
    }

    // MARK: - Request shape

    func testRequestBodyHasToolUseAndCacheControl() throws {
        let provider = AnthropicProvider(apiKey: "sk", transport: FakeTransport(responses: []))
        let body = provider.makeRequestBody(redactedText: "[redacted]", hints: ExtractionHints())
        let dict = try JSONSerialization.jsonObject(with: body) as! [String: Any]

        XCTAssertEqual(dict["model"] as? String, "claude-sonnet-4-6")

        let toolChoice = dict["tool_choice"] as! [String: Any]
        XCTAssertEqual(toolChoice["type"] as? String, "tool")
        XCTAssertEqual(toolChoice["name"] as? String, ExtractionPromptV1.toolName)

        let system = dict["system"] as! [[String: Any]]
        let cacheControl = system.first?["cache_control"] as? [String: Any]
        XCTAssertEqual(cacheControl?["type"] as? String, "ephemeral")

        let tools = dict["tools"] as! [[String: Any]]
        XCTAssertEqual(tools.first?["name"] as? String, ExtractionPromptV1.toolName)
        XCTAssertNotNil(tools.first?["input_schema"])
    }

    // MARK: - Helpers

    private func makeCannedResponseJSON() -> Data {
        let toolInput: [String: Any] = [
            "statement": [
                "issuer": "MockBank",
                "currency": "BRL",
                "totals": ["current_charges_total": 100.00],
            ],
            "cards": [
                ["last4": "0001", "holder_name": "A", "subtotal": 100.00],
            ],
            "transactions": [
                [
                    "card_last4": "0001",
                    "posted_date": "2026-04-01",
                    "posted_year_inferred": false,
                    "raw_description": "X",
                    "merchant": "X",
                    "amount": 100.00,
                    "currency": "BRL",
                    "purchase_method": "physical",
                    "transaction_type": "purchase",
                    "confidence": 0.99,
                ],
            ],
            "warnings": [],
        ]
        let response: [String: Any] = [
            "id": "msg_test",
            "model": "claude-sonnet-4-6",
            "stop_reason": "tool_use",
            "content": [
                [
                    "type": "tool_use",
                    "id": "toolu_test",
                    "name": ExtractionPromptV1.toolName,
                    "input": toolInput,
                ],
            ],
            "usage": [
                "input_tokens": 1234,
                "output_tokens": 567,
                "cache_creation_input_tokens": 0,
                "cache_read_input_tokens": 1000,
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: response)
    }
}

// MARK: - Fake transport

private final class FakeTransport: AnthropicTransport, @unchecked Sendable {
    var queued: [(Data, Int)]
    private(set) var callCount = 0
    private let lock = NSLock()

    init(responses: [(Data, Int)]) {
        self.queued = responses
    }

    func send(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        callCount += 1
        guard !queued.isEmpty else {
            lock.unlock()
            throw LLMError.network(statusCode: 0, body: "fake transport exhausted")
        }
        let (data, code) = queued.removeFirst()
        lock.unlock()
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: code,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (data, http)
    }
}
