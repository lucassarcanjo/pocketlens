# LLM Integration

PocketLens uses large language models as an **optional assistant**, never as the source of truth. Parsing, storage, rules, and dashboards all work with no LLM configured.

## Principles

1. **Opt-in.** Default mode is "No LLM". Every cloud call requires explicit consent.
2. **Summaries, not raw data.** Monthly explanations receive aggregates; per-transaction categorization receives one transaction plus a small context window, never an entire statement.
3. **Redaction by default.** The `DataRedactor` removes account numbers, full card digits, person names before any outbound call.
4. **Auditability.** All prompts live in one file (`PromptBuilder.swift`). Snapshot tests lock them down.
5. **Local-first.** Ollama is a first-class provider.

## Provider Protocol

```swift
protocol LLMProvider {
    func categorize(
        transaction: Transaction,
        context: CategorizationContext
    ) async throws -> CategorizationSuggestion

    func explainMonth(
        summary: MonthlySummary
    ) async throws -> String
}
```

Concrete providers:

| Provider | Use | Network |
|---|---|---|
| `MockProvider` | Tests; deterministic responses | None |
| `OllamaProvider` | Local LLM via Ollama | `http://localhost:11434` (default) |
| `OpenAIProvider` | Cloud, OpenAI API | `api.openai.com` |
| `AnthropicProvider` | Cloud, Anthropic API | `api.anthropic.com` |

## Where LLMs Fit

Per [`categorization.md`](categorization.md), LLM suggestions are **priority 6** in the engine — tried only when exact user corrections, merchant aliases, user rules, keyword rules, and similarity all miss. The suggestion is stored alongside the transaction and surfaced in the review UI; it's **not auto-applied** unless the user raises the auto-apply threshold in Settings.

Beyond categorization, LLMs are used for:

- **"Explain this month"** — receives an aggregate `MonthlySummary`, returns a short narrative.
- **Rule suggestions** — after several user corrections in the same merchant or category, the LLM can propose a rule.
- **Anomaly hints** (future) — spotting unusual spending in the monthly summary.

## Context Objects

### `CategorizationContext`

Sent with each `categorize` call:

- The user's current category list (names + descriptions).
- A small window of recent similar transactions (normalized descriptions + categories).
- Any merchant alias the normalizer already associated with this transaction.

Crucially, the raw PDF, the full statement, and other transactions' amounts are **not** included.

### `MonthlySummary`

Sent with `explainMonth`:

- Total spending for the period (per currency).
- Breakdown by category (top N with long tail grouped into "Other").
- Top merchants by spend.
- Largest N transactions (descriptions + amounts; no account numbers).
- Comparison to prior month (deltas, not raw values of prior periods).

## Prompts

Prompts are generated centrally by `PromptBuilder.swift`. Each prompt is versioned (`prompt_version: "v1"` etc.) so we can reason about drift.

Example categorization prompt shape (illustrative, subject to tuning):

```
System: You are a financial transaction categorizer. Given a transaction,
return a JSON object {category: string, confidence: number, reason: string}.
Categories available: [Groceries, Restaurants, ...].

User: Transaction:
  Description: <normalized>
  Amount: <value> <currency>
  Date: <date>
  (Installment 3 of 12, if applicable)

Recent similar transactions you previously categorized:
  <up to 5 (description, category) pairs>

Respond with JSON only.
```

The real prompt lives in code. This document tells you where to look (`packages/LLM/Sources/LLM/PromptBuilder.swift`) and what the contract is.

## Cost & Rate Limits

- Per-provider cost estimation surfaces in Settings (planned for Phase 5).
- A simple in-memory LRU cache short-circuits duplicate categorization calls on identical normalized descriptions.
- Users can cap monthly spend by setting a suggestion threshold — below it, no LLM call is made.

## API Key Management

- Stored in macOS Keychain exclusively.
- Settings UI masks keys behind "••••••" with a reveal-on-click.
- Keys are scoped per-provider; deleting a provider wipes its key.

## Testing

- `MockProvider` satisfies the protocol with deterministic responses — used by higher-level tests.
- Prompt text is covered by snapshot tests so silent drift is caught in review.
- Integration tests for real providers run only when an env var (`POCKETLENS_LLM_INTEGRATION=1`) is set, to avoid spending credits in normal CI.
