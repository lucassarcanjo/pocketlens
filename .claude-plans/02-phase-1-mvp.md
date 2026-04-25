# Phase 1 — MVP: LLM-Powered Statement Import (v0.1)

## Goal

A user drops a credit-card-statement PDF into PocketLens. The app extracts text with PDFKit, sends a version to Anthropic's Claude, gets back a structured `ExtractedStatement` JSON, validates it against the printed totals on the statement, persists it locally, and lets the user review and edit categories. There is **no bank-specific parser code**. Adding a new issuer is a fixture + (occasionally) a small prompt addendum, not a new Swift class.

The "Anthropic does the extraction" fact is disclosed twice, low-friction: once at first-launch onboarding (alongside the API-key paste field) and again as a one-liner on the drop zone itself. Uploading a PDF *is* the consent — there's no modal sheet. PocketLens has no non-LLM operating mode; if a user doesn't want their statement text to reach an LLM, this app isn't for them.

## Definition of Done

- [ ] User opens app and sees a sidebar window: Transactions / Imports / Categories / Dashboard (placeholder) / Settings.
- [ ] First-launch onboarding screen: one-liner disclosure ("PocketLens uses Anthropic Claude to read your statement PDFs. Your data is sent to Anthropic but not used for training. Full card numbers, CPF, and addresses are redacted before upload."), a "Learn more" link to `docs/privacy.md`, and the Anthropic API key paste field. The app refuses to import until a key is set.
- [ ] User imports a PDF via drag-and-drop or `File → Import…`. The drop zone shows an inline disclosure: "By uploading, you agree to send the redacted text to Anthropic Claude (not used for training)."
- [ ] Extraction runs with progress UI: `extracting text → calling Claude → validating → saving`.
- [ ] Transactions appear in a sortable `Table`, **grouped by card** (one section per `Card`).
- [ ] Each row shows: date, merchant (raw + normalized), amount + currency, card last-4, holder, installment N/M (if any), bank-category-raw, app-category (editable), purchase method icon (virtual / digital_wallet / physical), confidence.
- [ ] User can change a transaction's app-category from a fixed seed list (full CRUD deferred to Phase 2).
- [ ] Re-importing the same PDF (same SHA-256) is rejected with a clear "already imported as batch #N on YYYY-MM-DD" message.
- [ ] Re-importing an overlapping statement deduplicates at the transaction level via fingerprint.
- [ ] Validation: per-card extracted sums must match the per-card totals printed on the PDF (e.g., "Lançamentos no cartão (final 1111) 7.473,18") within ±R$0.01. Grand total must match "Total dos lançamentos atuais". Mismatch → import marked `needs_review` and warning surfaced.
- [ ] Forecast section ("Compras parceladas - próximas faturas") is correctly **excluded**.
- [ ] Imports view lists every `ImportBatch` with: file name, statement period, total, transaction count, LLM model + tokens + cost, validation status.
- [ ] All data persists to `~/Library/Application Support/PocketLens/pocketlens.db` (GRDB).
- [ ] Settings → LLM: manage Anthropic key (rotate / delete); pick model. No "privacy mode" toggle — the app is LLM-only by design.
- [ ] Default categories from spec §19 seeded on first run.
- [ ] `make test` passes — including a Mock-LLM-driven extraction test against the reference fixture.

## Architecture: New Import Flow

```
PDF (drop / picker)
  ↓ SHA-256 (file-level dedup) — already imported? halt with friendly message
  ↓ PDFTextExtractor (PDFKit, page-by-page)
  ↓ Redactor (mask CPF, full card number, full address; preserve last-4 + city)
  ↓ AnthropicProvider.extractStatement(text) — tool-use with strict schema, prompt-cached
  ↓ ExtractedStatement (Codable DTO)
  ↓ ExtractionValidator (per-card + grand-total checksum vs printed totals)
  ↓ MerchantNormalizer (strip installment marker from raw, casefold, collapse whitespace)
  ↓ DeduplicationEngine (transaction-fingerprint dedup)
  ↓ Persist in one GRDB write transaction:
      ImportBatch + Cards (upsert) + Merchants (upsert) + Transactions
  ↓ UI refresh
```

## Reference Fixture

`fixtures/statements/itau-personnalite-2026-03-private.pdf` — Itaú Personnalité Mastercard Black, statement closing 2026-03-30, due 2026-04-06. **Gitignored** (`*-private.pdf`).

What the fixture exercises (this is the spec for the extraction prompt):
- **Multi-card statement.** Three cards on one PDF:
  - 1111 — JOHN A DOE (main holder) — total R$ 7.473,18
  - 2222 — JOHN A DOE (additional card, same holder) — total R$ 4.542,90
  - 3333 — JANE B SMITH (additional card, different holder) — total R$ 4.248,98
  - Plus "Lançamentos internacionais" (USD-origin) under card 2222 — R$ 334,79 (incl. IOF R$ 11,34)
  - Grand total: R$ 16.599,85
- **Per-line shape (national):** `DD/MM ESTABLISHMENT [N/M] AMOUNT` followed by `CATEGORY .CITY` line.
- **Installment marker:** `06/10` after merchant = installment 6 of 10. The amount on the line is the per-installment amount.
- **Year inference:** statement only prints DD/MM. The model must infer the year from statement period + installment context (e.g., `02/10 ... 06/10` in a 2026-03 statement → original purchase 2025-10-02).
- **Transaction-method glyphs:** an `@` icon prefix means `virtual_card`; a digital-wallet glyph means `digital_wallet`; otherwise `physical`. (PDFKit doesn't surface the glyph reliably — we send page-by-page raw text and let the model use surrounding cues.)
- **International section:** different shape — merchant + city + original amount + currency + USD column + BRL column + conversion rate. Plus a separate `Repasse de IOF` line that we model as a fee transaction, not folded into purchase amounts.
- **Forecast section ("Compras parceladas - próximas faturas"):** lists installments scheduled for FUTURE statements. Must NOT be imported as transactions for this batch. The prompt enumerates section headers to ignore.
- **Statement headers:** total, due date, closing date, previous balance, payment received, revolving balance — extracted into `ImportBatch`.
- **Per-card subtotal lines** ("Lançamentos no cartão (final XXXX) 7.473,18") are the validation checksums.

## Tasks

### Domain package

- [ ] `Money` value type — Decimal-backed, `currency: Currency`, equality, hashable, locale-safe formatter, arithmetic that preserves currency.
- [ ] `Currency` enum: `BRL | USD | EUR | GBP` (extensible).
- [ ] `TransactionType` enum: `purchase | refund | payment | fee | iof | adjustment`.
- [ ] `PurchaseMethod` enum: `physical | virtualCard | digitalWallet | recurring | unknown`.
- [ ] `Installment` value type: `current: Int, total: Int`.
- [ ] `Account` — `id, bankName, accountAlias, holderName, createdAt`.
- [ ] `Card` — `id, accountId, last4, holderName, network, tier?, nickname?`.
- [ ] `Merchant` — `id, raw, normalized, defaultCategoryId?` (alias table comes Phase 2).
- [ ] `Category` — `id, parentId?, name, color?, icon?`.
- [ ] `Transaction`:
  - `id, importBatchId, cardId, postedDate, postedYearInferred: Bool`
  - `merchantId, rawDescription, merchantNormalized, merchantCity?, bankCategoryRaw?`
  - `amount: Money` (always BRL on storage), `originalAmount: Money?, fxRate: Decimal?`
  - `installment: Installment?`
  - `purchaseMethod, transactionType`
  - `categoryId?, confidence: Double, categorizationReason: String` (Phase 2 fills this — empty in Phase 1)
  - `fingerprint: String` (computed)
  - `createdAt, updatedAt`
- [ ] `ImportBatch`:
  - `id, sourceFileName, sourceFileSha256, sourcePages`
  - `statementPeriodStart, statementPeriodEnd, statementCloseDate, statementDueDate`
  - `statementTotal, previousBalance?, paymentReceived?, revolvingBalance?`
  - `llmProvider, llmModel, llmInputTokens, llmOutputTokens, llmCostUSD`
  - `validationStatus: enum { ok, warning, failed }`, `parseWarnings: [String]`
  - `importedAt`
- [ ] `ExtractedStatement` DTO (Codable) — pure shape returned by the LLM tool call. Lives in `LLM` package, not `Domain`, because it is provider-bound.

### LLM package (pulled forward from Phase 5)

- [ ] `LLMProvider` protocol:
  ```swift
  protocol LLMProvider {
      var name: String { get }
      var model: String { get }
      func extractStatement(text: String, hints: ExtractionHints) async throws -> ExtractionResult
      // Phase 2+: categorize(...)  Phase 5+: summarize(...)
  }
  ```
  - `ExtractionHints` carries known-issuer fingerprints and the user's BRL locale.
  - `ExtractionResult` wraps the `ExtractedStatement` plus token usage + cost.
- [ ] `MockLLMProvider` — deterministic; loads canned `ExtractedStatement` JSON from a test bundle. Backs all parser tests.
- [ ] `AnthropicProvider`:
  - URLSession HTTP client, no third-party SDK (small surface).
  - Default model: `claude-sonnet-4-6`. Settings allows `claude-opus-4-7`.
  - **Prompt caching**: cache the system prompt + tool schema (`cache_control: {type: "ephemeral"}` on the system block). Variable per-call: redacted statement text.
  - **Tool-use** (strict): single tool `record_extracted_statement` whose JSON schema mirrors `ExtractedStatement`. `tool_choice: {type: "tool", name: "record_extracted_statement"}` forces structured output.
  - Streaming: NO for v0.1 (small structured payload, simpler).
  - Cost tracking: parse `usage` from response; convert to USD via a small static price table keyed by model.
- [ ] `KeychainStore` — read/write `pocketlens.anthropic_api_key`.
- [ ] `Redactor`:
  - Mask full card number → keep `XXXX.XXXX.XXXX.NNNN` last 4.
  - Strip CPF (`\d{3}\.\d{3}\.\d{3}-\d{2}`) and CNPJ.
  - Replace street address line with `[ADDRESS]`; keep city + state.
  - Pluggable rule list so a contributor can add patterns without surgery.
- [ ] **Prompt** — `ExtractionPromptV1.swift`. Versioned constant. Contains:
  - System message: role, output discipline, year-inference rules, sections to ignore (forecast, summary boxes, installment-simulation tables), how to encode multi-card grouping, rules for international transactions and IOF, glyph hints (`@`, digital wallet).
  - Tool schema: every field of `ExtractedStatement`.
  - One redacted few-shot example (1 card, 3 transactions including 1 installment) so the model anchors on shape.
- [ ] `PromptVersion` constant stamped onto every `ImportBatch` (so we can detect drift later).

### Persistence package

- [ ] **Library: GRDB.swift v6.x** (decision locked). Add to `packages/Persistence/Package.swift` deps.
- [ ] `SQLiteStore` — opens/creates DB at `~/Library/Application Support/PocketLens/pocketlens.db`. Enables `PRAGMA foreign_keys = ON` and `journal_mode = WAL`.
- [ ] `Migrations` registry — Schema v1 covers Phase 1 entities (see `docs/data-model.md`).
- [ ] Repositories: `AccountRepository, CardRepository, MerchantRepository, CategoryRepository, ImportBatchRepository, TransactionRepository`. Each exposes async CRUD.
- [ ] `DefaultDataSeeder`:
  - Seed categories per spec §19 on first run.
  - Seed Itaú as the first known bank (more added as fixtures arrive).
- [ ] All persistence writes from a single import wrapped in one `db.write { ... }`.

### Importing package

- [ ] `PDFTextExtractor` — PDFKit `PDFDocument` → page-keyed text dictionary; preserves page boundaries (the model uses them).
- [ ] `LLMStatementExtractor` — top-level orchestrator: redact → provider call → validate → return `ExtractedStatement`.
- [ ] `ExtractionValidator`:
  - Per-card-subtotal vs sum of card's transactions: ±R$0.01.
  - Grand total vs sum of all transactions: ±R$0.01.
  - International section sum vs `Total lançamentos inter. em R$`.
  - Confidence floor: warn if >2% of transactions have `confidence < 0.7`.
  - Schema validation: required fields populated, dates valid, currencies recognized.
- [ ] `MerchantNormalizer`:
  - Casefold, collapse whitespace.
  - Strip trailing installment marker (`\b\d{1,2}/\d{1,2}\s*$` from raw description, since the LLM may or may not).
  - Strip leading provider prefixes (`MP *`, `IFD*`, `PIX*`).
- [ ] `DeduplicationEngine`:
  - File-level: SHA-256 of original PDF bytes, unique constraint on `import_batches.source_file_sha256`.
  - Transaction fingerprint: `posted_date|merchant_normalized|amount|currency|card_last4|installment_current|installment_total|purchase_method`.
- [ ] `ImportPipeline` — public façade, takes a `URL`, returns `ImportResult` (batch id + warnings + counts).

### App target

- [ ] `MainWindow` with `NavigationSplitView`: Transactions / Imports / Categories / Dashboard (placeholder) / Settings.
- [ ] `OnboardingView` — first-launch flow that explains the data path (redacted text → Anthropic Claude), shows what gets redacted, links to `docs/privacy.md`, and collects the Anthropic API key. Saves into Keychain. Cannot proceed without a key.
- [ ] `ImportDropZone` overlay on TransactionsView.
- [ ] `FileImporter` sheet for `File → Import…` and `⌘O`.
- [ ] `ImportProgressSheet` — phase indicators + cancel button.
- [ ] `TransactionsView` — `Table` grouped by card section. Editable category column via inline picker.
- [ ] `ImportsView` — list of `ImportBatch` with summary metrics + validation badge.
- [ ] `CategoriesView` — read-only list (full CRUD in Phase 2).
- [ ] `SettingsView`:
  - Anthropic API Key (Keychain, masked, reveal-on-click; rotate / delete)
  - Model picker (Sonnet 4.6 default; Opus 4.7 alternate)
  - Link out to `docs/privacy.md`
  - "Reset Database" with hard confirmation

## Files Touched (anticipated)

- `packages/Domain/Sources/Domain/{Money,Currency,Enums,Account,Card,Merchant,Category,Transaction,ImportBatch}.swift`
- `packages/LLM/Sources/LLM/{LLMProvider,ExtractedStatement,ExtractionResult,MockLLMProvider,AnthropicProvider,KeychainStore,Redactor,ExtractionPromptV1,Pricing}.swift`
- `packages/Persistence/Sources/Persistence/{SQLiteStore,Migrations,Schema_v1,Repositories,DefaultDataSeeder}.swift`
- `packages/Importing/Sources/Importing/{PDFTextExtractor,LLMStatementExtractor,ExtractionValidator,MerchantNormalizer,DeduplicationEngine,ImportPipeline}.swift`
- `app/PocketLens/Views/{MainWindow,TransactionsView,ImportsView,CategoriesView,SettingsView,OnboardingView,ImportProgressSheet,ImportDropZone}.swift`
- `app/PocketLens/ViewModels/{TransactionsViewModel,ImportsViewModel,SettingsViewModel}.swift`
- `app/project.yml` — add GRDB SPM dep; `LLM` package gets the Anthropic networking code (no extra dep).

## Dependencies

- Phase 0 ✅
- Network access for Anthropic API
- User-provided Anthropic API key (stored in Keychain)
- App Sandbox is currently **disabled** (entitlements is empty `<dict/>`). Phase 1 stays sandbox-off; we'll re-enable in Phase 6 after the folder-watcher security-scoped-bookmark plumbing exists.

## Test Coverage

- **Domain unit tests:** `Money` arithmetic + currency safety; fingerprint stability; enum exhaustiveness.
- **Persistence:** v1 migration applies to a fresh DB; seeder is idempotent; CRUD round-trip for each repo.
- **Redactor tests:** card number / CPF / address scrubbed; merchant names + cities preserved.
- **Mock-LLM extraction tests** (the centerpiece — no network):
  - Reference fixture → MockLLMProvider returns canned `ExtractedStatement` → pipeline produces exactly the expected transaction count and totals.
  - Multi-card grouping correct.
  - Installment parsing correct (current vs total; per-installment amount as line amount).
  - International transactions parsed with `originalAmount` + `fxRate`.
  - IOF stored as a separate `transaction_type = .iof` row.
  - Forecast section is NOT imported.
- **Validator tests:** intentionally-broken extractions (missing transaction, wrong subtotal) trigger correct warnings.
- **Dedup tests:** same file twice; overlapping statement; same merchant/date/amount but different installment → both kept.
- **AnthropicProvider integration test (opt-in):** runs only when `POCKETLENS_LLM_INTEGRATION=1` is set; hits real API with a tiny redacted snippet. Asserts the JSON shape, not the values. Gated by `make test-integration`.
- **PDFTextExtractor test:** loads the reference PDF (gitignored — guard with `#if FIXTURE_PRESENT`), asserts page count and that key strings appear on expected pages.

## Open Questions

1. **Anthropic Swift SDK or roll-your-own?** Recommend roll-your-own URLSession+JSON. The surface is one POST and a typed response; pulling a third-party SDK adds maintenance.
2. **Default model:** `claude-sonnet-4-6` is the recommendation (cheaper + fast enough on a 5–6 page statement). Opus 4.7 is offered for fallback when Sonnet fails validation.
3. **Cost ceiling per import:** warn at $0.50, hard-stop at $2.00 (configurable). Reasonable for a 5–10 page statement at Sonnet pricing.
4. **Glyph fidelity:** PDFKit's text extraction may drop the `@` virtual-card glyph and the digital-wallet icon. We send page-by-page raw text and instruct the model to be lenient — `purchase_method = "unknown"` is acceptable when it can't determine. Better than guessing.
5. **Year inference correctness:** the prompt instructs the model to compute year from statement close date + (for installments) `(close_date.year * 12 + close_date.month - (total_installments - current_installment + 1))`. We'll verify against the fixture and add tests.

## Next Action

Confirm this plan with the user, then start with the **Domain** package (Money + enums + entities). Domain unblocks both LLM (which produces `ExtractedStatement` mirroring Domain shapes) and Persistence (which stores them). Once Domain compiles, the order is: ExtractedStatement DTO + MockLLMProvider + extraction prompt → PDFTextExtractor → ExtractionValidator → end-to-end fixture test passing → AnthropicProvider → Persistence + repositories → app UI.
