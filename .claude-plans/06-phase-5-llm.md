# Phase 5 — LLM (v0.5)

## Goal
Optional AI assistance for categorization, monthly explanations, and rule suggestions — with explicit user consent and a visible data-flow story. The core app must still work without any LLM configured.

## Definition of Done (per spec §13)
- [ ] `LLMProvider` protocol with `categorize` and `explainMonth` methods.
- [ ] Four concrete providers: `MockProvider`, `OllamaProvider`, `OpenAIProvider`, `AnthropicProvider`.
- [ ] API keys stored in macOS Keychain; never written to disk in plaintext.
- [ ] Privacy Mode setting (spec §13.3): `No LLM | Local LLM | Cloud LLM`.
- [ ] Consent dialog before first cloud LLM call showing exactly what will be sent.
- [ ] Low-confidence transactions get an LLM categorization suggestion (priority 6 in §11.1).
- [ ] Monthly explanation feature on dashboard ("Explain this month" button, spec §8.4).
- [ ] Rule suggestions — LLM proposes rules after bulk corrections.
- [ ] Full PDF content NEVER sent to cloud providers. Only summarized transaction data.

## Tasks

### LLM package
- [ ] `LLMProvider` protocol matching spec §13.1 signature.
- [ ] `CategorizationContext` value type — includes recent user corrections, category list, merchant aliases.
- [ ] `MonthlySummary` value type — aggregates (NOT raw transaction lines) for `explainMonth`.
- [ ] `MockProvider` — returns deterministic fake responses for tests.
- [ ] `OllamaProvider` — HTTP POST to user-configured endpoint (default `http://localhost:11434`).
- [ ] `OpenAIProvider` — uses Keychain-stored API key, respects model selection.
- [ ] `AnthropicProvider` — uses Keychain-stored API key.
- [ ] `PromptBuilder` — generates the prompts per task type, with a central place to audit them.
- [ ] `DataRedactor` — strips account numbers, card digits, person names from anything sent to cloud providers.

### Persistence
- [ ] Store LLM suggestions separately from user-confirmed categorizations so we can tell them apart.
- [ ] Cache recent LLM responses (optional; reduces cost + latency).

### App target
- [ ] Settings → LLM section: provider picker, Ollama endpoint, API key fields (Keychain-backed), model selection per provider.
- [ ] Privacy Mode radio.
- [ ] Consent dialog component.
- [ ] "Explain this month" button + result view (plain text, copyable).
- [ ] LLM suggestion surfacing in the review screen (badge + one-click accept/reject).

## Dependencies
- Requires Phase 2 ✅ (categorization priority chain has a slot for LLM suggestions).
- Requires Phase 3 ✅ (dashboard's monthly summary is the input to `explainMonth`).

## Test Coverage
- Prompt snapshot tests — lock down the exact prompt text sent to each provider.
- Redactor tests — assert sensitive fields are gone from redacted payloads.
- MockProvider fulfills the protocol and supports all higher-level tests without network.
- Privacy Mode tests — in `No LLM`, assert no provider is ever invoked; in `Local LLM`, assert only Ollama.

## Open Questions
- Default model choices per provider (likely claude-sonnet-4-6 and gpt-4o-mini; check cost/latency tradeoff).
- Whether to pre-compute embeddings locally for similarity (or rely on Phase 2's lexical similarity).
- Rate limiting and cost display — surface an estimated monthly spend in Settings.

## Next Action
Write the `LLMProvider` protocol + `MockProvider` first. Then build Settings UI + Privacy Mode gating before wiring any real providers.
