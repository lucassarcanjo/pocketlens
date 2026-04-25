# Phase 5 — LLM Expansion (v0.5)

## Context

The LLM **provider abstraction**, **Anthropic provider**, **Keychain key storage**, **redaction**, **first-launch disclosure**, and **structured-output extraction** all shipped in Phase 1 because the MVP import path depends on them. This phase fills out the rest of spec §13: a local-LLM path, additional cloud providers, and assistant features that go beyond extraction.

## Goal

Make LLM use flexible (provider-agnostic), local-friendly (Ollama), and useful beyond extraction (categorization assist, monthly explanation, rule suggestions). PocketLens remains LLM-only — there is still no "no LLM" mode and no manual-entry fallback.

## Definition of Done

- [ ] `OllamaProvider` works against a user-configured endpoint (default `http://localhost:11434`) and a user-chosen local model.
- [ ] `OpenAIProvider` works against `api.openai.com` with a Keychain-stored key.
- [ ] Provider picker in Settings — single global selection (Anthropic / OpenAI / Ollama). Per-feature overrides are deferred unless real usage demands them.
- [ ] The drop-zone disclosure line updates to match the active provider: "Anthropic Claude" / "OpenAI" / "your local Ollama instance".
- [ ] Selecting Ollama auto-detects whether the endpoint is reachable; if not, the import button is disabled with an inline hint.
- [ ] **Categorization assist:** for low-confidence transactions (priority 6 in §11.1), the configured provider proposes a category. Surfaces as a badge in the review UI; one-click accept/reject.
- [ ] **"Explain this month":** dashboard button generates a short narrative from `MonthlySummary` aggregates (NOT raw transactions).
- [ ] **Rule suggestions:** after several user corrections in the same merchant/category, the configured provider proposes a `CategorizationRule`.
- [ ] Cost dashboard in Settings — running totals per provider per month, sourced from `import_batches.llm_cost_usd` and a new `llm_calls` table.
- [ ] Prompt-snapshot tests cover all task types so silent drift is caught in PR review.

## Tasks

### LLM package

- [ ] `OllamaProvider` — POST `/api/chat` with the user's chosen model. Streaming optional. No API key required.
- [ ] `OpenAIProvider` — Chat Completions API; tool-use mode for structured outputs.
- [ ] Extend `LLMProvider` protocol:
  ```swift
  func categorize(transaction: Transaction, context: CategorizationContext) async throws -> CategorizationSuggestion
  func summarizeMonth(summary: MonthlySummary) async throws -> String
  func suggestRule(corrections: [UserCorrection]) async throws -> CategorizationRuleDraft?
  ```
- [ ] `CategorizationContext` — current category list + merchant alias (if any) + up to 5 recent similar (description, category) pairs. Crucially: NO statement-level data, NO unrelated transactions.
- [ ] `MonthlySummary` — top-level totals + category breakdown + top merchants + largest N transactions (descriptions only, no card numbers). NEVER includes raw statement data.
- [ ] `PromptCatalog` — replaces `ExtractionPromptV1` with a registry of versioned prompts per task; each task picks its prompt version explicitly. Snapshot tests lock down the text.
- [ ] `ProviderRegistry` — single source of truth for the active provider. Each task (`extract`, `categorize`, `summarize`) reads it lazily.

### Persistence

- [ ] `llm_calls` table — `id, provider, model, task, input_tokens, output_tokens, cost_usd, created_at, related_entity_id`. Drives the cost dashboard.
- [ ] `llm_suggestions` table — caches `categorize` results so repeated reviews of the same transaction don't re-spend.

### App target

- [ ] Settings → LLM section: per-feature provider picker + endpoint/model fields + Keychain key inputs.
- [ ] "Explain this month" button on Dashboard (Phase 3 ships dashboard; this phase wires the LLM call to it).
- [ ] LLM-suggested category badge in Transactions table; one-click accept/reject.
- [ ] Rule-suggestion sheet that appears after N (default 3) consistent corrections in the same merchant.
- [ ] Cost dashboard view in Settings.

## Dependencies

- Phase 1 ✅ — provider protocol + Anthropic + redaction + Keychain + first-launch disclosure already exist.
- Phase 2 ✅ — categorization priority chain has the slot for LLM suggestions.
- Phase 3 ✅ — dashboard provides `MonthlySummary` aggregates.

## Test Coverage

- `MockLLMProvider` extended with deterministic `categorize / summarizeMonth / suggestRule` responses.
- Snapshot tests for every prompt template.
- Redactor regression tests — assert all task contexts pass through redaction (not just extraction).
- Provider-routing tests — switching the active provider in Settings sends every subsequent task to the new provider and only the new provider; no accidental fallback.
- Cost-tracking tests — `llm_calls` rows accumulate correctly; dashboard query returns expected aggregates.

## Open Questions

- Default Ollama model recommendation (`llama3.2`? `qwen2.5`? `deepseek-r1` for reasoning?). Document in `llm-integration.md` as a "Tested with…" matrix.
- Whether to attempt local extraction with Ollama at all in v0.5 or restrict local mode to categorization/summary (extraction needs strong tool-use; many local models stumble). Lean toward: extraction stays cloud-required in v0.5, local handles the lighter tasks. Re-evaluate with newer local models.
- Cost-control mechanism — soft warning vs hard cap vs monthly budget.

## Next Action

Add `OllamaProvider` with a 3-line system prompt and a `summarize` task as the smoke test. Validate the routing layer with Privacy-Mode tests before exposing the provider picker in Settings.
