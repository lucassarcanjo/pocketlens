# LLM Integration

PocketLens uses an LLM to **extract structured transactions from arbitrary statement PDFs**. Unlike a traditional finance app, there is no per-bank parser code — the prompt + a strict JSON schema is the contract. The same flow handles Itaú today and a different issuer tomorrow with at most a small prompt addendum.

This document describes how that integration is structured, what data crosses the network, and how to extend it.

## Design principles

1. **Structured output is non-negotiable.** All LLM calls use tool-use mode with a strict JSON schema. Free-form text responses are never trusted.
2. **The prompt is versioned.** Every `ImportBatch` records `llm_provider`, `llm_model`, and `prompt_version` so we can detect drift and reproduce results.
3. **Pre-LLM redaction is mandatory.** Full card numbers, CPF/CNPJ, and street addresses never leave the device.
4. **Disclosure is structural, not modal.** The app *is* an LLM-extraction tool — there is no non-LLM mode. Disclosure shows up twice as inline text: a one-liner on first-launch onboarding (next to the API-key field) and a one-liner on the drop zone ("By uploading, you agree to send the redacted text to <provider>"). Uploading a file is the consent act. No per-import sheet.
5. **Validation against ground truth.** The PDF prints per-card and grand totals. We sum the extracted transactions and assert match within R$0.01. Mismatches surface as `validation_status = warning` on the batch — never silently accepted.
6. **Cost is tracked.** Token counts and USD cost stored on every batch + every assist call.
7. **The Mock provider runs all tests.** No CI minute spends a cent.

## Provider protocol

```swift
protocol LLMProvider {
    var name: String { get }    // "anthropic" | "openai" | "ollama" | "mock"
    var model: String { get }   // e.g. "claude-sonnet-4-6"

    /// Phase 1 — required for import.
    func extractStatement(text: String, hints: ExtractionHints) async throws -> ExtractionResult

    /// Phase 2+ — categorization assist.
    func categorize(transaction: Transaction, context: CategorizationContext) async throws -> CategorizationSuggestion

    /// Phase 5+ — narrative summary.
    func summarizeMonth(summary: MonthlySummary) async throws -> String
}
```

| Provider | Status | Network | Use |
|---|---|---|---|
| `MockLLMProvider` | Phase 1 | None | Tests; deterministic canned responses |
| `AnthropicProvider` | Phase 1 | `api.anthropic.com` | Default cloud provider |
| `OllamaProvider` | Phase 5 | `localhost:11434` (default) | Local-only LLM |
| `OpenAIProvider` | Phase 5 | `api.openai.com` | Alternate cloud provider |

## ExtractedStatement schema (Phase 1 contract)

The tool schema sent to Claude. Mirrors what we persist (close to, but not identical to, the SQLite shape — DB ids and timestamps are added on insert).

```jsonc
{
  "statement": {
    "issuer": "string",                       // e.g. "Itaú Personnalité"
    "product": "string",                      // e.g. "Mastercard Black"
    "period_start": "YYYY-MM-DD",
    "period_end": "YYYY-MM-DD",               // closing date
    "due_date": "YYYY-MM-DD",
    "currency": "BRL",
    "totals": {
      "previous_balance": "number",
      "payment_received": "number",
      "revolving_balance": "number",
      "current_charges_total": "number"       // matches "Total dos lançamentos atuais"
    }
  },
  "cards": [
    {
      "last4": "1111",
      "holder_name": "JOHN A DOE",
      "network": "Mastercard",
      "tier": "Black",                         // optional
      "subtotal": "number"                     // matches "Lançamentos no cartão (final XXXX)"
    }
  ],
  "transactions": [
    {
      "card_last4": "1111",
      "posted_date": "YYYY-MM-DD",
      "posted_year_inferred": true,            // statement printed only DD/MM
      "raw_description": "VIVARA BBH 06/10",
      "merchant": "VIVARA BBH",
      "merchant_city": "BELO HORIZONTE",
      "bank_category_raw": "DIVERSOS",         // issuer-provided category, when present
      "amount": "number",                      // per-installment amount on installment lines
      "currency": "BRL",
      "original_amount": null,                 // populated for international transactions
      "original_currency": null,
      "fx_rate": null,
      "installment_current": 6,                // null when not an installment line
      "installment_total": 10,
      "purchase_method": "physical",           // physical | virtual_card | digital_wallet | recurring | unknown
      "transaction_type": "purchase",          // purchase | refund | payment | fee | iof | adjustment
      "confidence": 0.97
    }
  ],
  "warnings": [
    "string"                                   // free-form notes from the model: e.g. "Glyph for line 12 ambiguous"
  ]
}
```

Fields **not** included by design:
- The forecast section "Compras parceladas - próximas faturas" — those are future-dated, not real transactions for this batch.
- Simulation tables ("Simulação de Compras parc. c/ juros…", "Simulação Saque Cash") — informational, not transactions.

## Anthropic provider specifics

- **Endpoint:** `POST https://api.anthropic.com/v1/messages`
- **Default model:** `claude-sonnet-4-6` (configurable to `claude-opus-4-7`).
- **Tool use (strict):** single tool `record_extracted_statement`, schema = `ExtractedStatement` above. `tool_choice: {"type":"tool","name":"record_extracted_statement"}` forces structured output.
- **Prompt caching:** the system prompt + tool schema (the constant ~3KB part) carry `cache_control: {"type":"ephemeral"}`. After the first call in a 5-minute window, subsequent imports save ~90% of input cost.
- **Streaming:** off in Phase 1 (small structured payload, simpler error handling).
- **Cost tracking:** parse `usage.input_tokens` + `usage.output_tokens` + `usage.cache_creation_input_tokens` + `usage.cache_read_input_tokens` from the response. A static price table (`Pricing.swift`) converts to USD and stores on `import_batches.llm_cost_usd`.
- **Error handling:** retries on 429/5xx with exponential backoff (3 attempts). Schema-validation failures from the model are NOT retried — they surface as `ImportError.invalidExtraction` so the user can investigate.

## The extraction prompt

Lives in `packages/LLM/Sources/LLM/ExtractionPromptV1.swift` — one constant, fully reviewable. The prompt covers:

1. **Role:** careful financial-statement parser; output JSON only via the tool.
2. **Output discipline:** never narrate; never include sections that are forecast/simulation/marketing.
3. **Multi-card grouping:** cards listed in `cards`; every transaction references its card by `card_last4`.
4. **Year inference rule:** statements print DD/MM only. Compute year from statement close date and (for installments) installment offset: `original_month = close_month - (total - current)`. Mark `posted_year_inferred = true`.
5. **Installment encoding:** the line amount is the per-installment amount. `installment_current` and `installment_total` populated from the `N/M` marker.
6. **International transactions:** fill `original_amount`, `original_currency`, `fx_rate`. The `Repasse de IOF` line is its own transaction with `transaction_type: "iof"`.
7. **Glyphs:** `@` prefix on a line ⇒ `purchase_method: virtual_card`; the small "Compra com carteira digital" glyph ⇒ `digital_wallet`. If unclear, `unknown` is acceptable.
8. **One redacted few-shot example** — a card header + 3 transaction lines (1 standard, 1 installment, 1 international) with the corresponding tool call.

The prompt version constant is stamped onto every `ImportBatch`. Bumping the version is the signal that historical batches may not be reproducible byte-for-byte.

## Privacy contract

- **Pre-LLM redaction.** `Redactor` strips full card numbers (keeps last 4), CPF/CNPJ patterns, and street addresses. Cities and states pass through (categorization needs them).
- **What's sent.** Only the redacted PDF text, plus the system prompt + tool schema (cached). No DB content. No prior transactions. No API keys other than Anthropic's auth header.
- **First-launch disclosure.** Onboarding shows what's sent, what's redacted, and links to [`privacy.md`](privacy.md). The user pastes their Anthropic key to proceed.
- **Drop-zone disclosure.** Inline text on the drop zone names the active provider and the "not used for training" promise. Uploading is the consent act.
- **No non-LLM mode.** PocketLens is LLM-only by design. Phase 5 lets users switch providers (Anthropic / OpenAI / Ollama); the disclosure line updates to match.

## Categorization assist (Phase 2+)

When a transaction's deterministic categorization (memory → alias → rule → similarity) misses, the configured provider is asked to suggest a category.

`CategorizationContext` carries:
- The user's category list (names + descriptions).
- Up to 5 recent (description, category) pairs **for this merchant or near-neighbors**.
- The merchant alias if any.

It does **not** carry: account numbers, statement-level data, unrelated transactions, or anything outside the small context window above. Suggestions are stored in `llm_suggestions` (cached) and surfaced as a badge in the review UI — never auto-applied unless the user raises the threshold in Settings.

## Monthly summary (Phase 5)

`MonthlySummary` carries aggregates only: per-category totals, top merchants, largest N transaction descriptions. Never raw rows. The summary is generated once and cached; rotating to a different model invalidates the cache.

## API key management

- `KeychainStore` (in `LLM` package) is the only code path that touches keys.
- Keys are written to macOS Keychain with `kSecAttrAccessibleWhenUnlocked`.
- Settings UI masks keys with reveal-on-click; they are never logged.
- Deleting a provider's key wipes only that provider's entry.

## Cost dashboard (Phase 5)

A new `llm_calls` table records every call (`provider, model, task, tokens, cost_usd, related_entity_id`). A Settings view rolls these up by month and provider.

## Testing

- `MockLLMProvider` returns deterministic canned `ExtractionResult` JSON loaded from a test bundle. Used by every parser test.
- Prompt snapshot tests guard `ExtractionPromptV1` and (Phase 5) every other prompt template against silent edits.
- Redactor regression tests run on a corpus of representative inputs.
- Anthropic integration test is **opt-in** via `POCKETLENS_LLM_INTEGRATION=1` and a real key. CI skips it by default; `make test-integration` runs it locally.
