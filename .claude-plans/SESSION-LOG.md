# PocketLens Session Log

Append-only log of Claude sessions. Most recent at the bottom.

---

## 2026-04-24 — Bootstrap: planning + repo scaffold

**Active phase:** 0 — Bootstrap
**Goal this session:** Create the cross-session planning infrastructure, concept docs, and a buildable empty SwiftUI app scaffold.

**Shipped:**
- `.claude-plans/` with `00-OVERVIEW.md`, `SESSION-LOG.md`, and 7 phase skeleton files.
- `docs/` with 8 concept markdown files (architecture, data-model, parsers, categorization, import-flow, privacy, llm-integration, contributing).
- Root tooling: `README.md`, `LICENSE` (MIT), `CONTRIBUTING.md`, `.gitignore`, `Makefile`, `project.yml`.
- `app/PocketLens/` SwiftUI placeholder app + `app/PocketLensTests/`.
- `packages/{Domain,Persistence,Importing,Categorization,LLM}/` empty SPM modules with trivial tests.
- `fixtures/{statements,expected-output}/` placeholder dirs.

**Decisions made:**
- XcodeGen over Tuist/manual Xcode/pure SPM — regenerable, VCS-friendly, minimal dependency.
- macOS 14 Sonoma minimum target — broad compatibility with modern SwiftUI/Swift Charts.
- MIT license — permissive, standard for consumer dev tools.
- 5 SPM packages (Domain, Persistence, Importing, Categorization, LLM) per spec §17.1; parsing lives inside Importing.

**Verification done this session:**
- All 5 SPM packages pass `swift test` on Swift 6.2 / Xcode 26 / arm64-apple-macos14.0.
- `make gen && make build && make test-app` succeeds end-to-end on user's machine.
- File tree matches the plan.

**Scaffold fixes applied mid-session:**
- Moved `project.yml` from repo root into `app/` so spec directory equals the Xcode `SRCROOT`. This was needed because XcodeGen writes `CODE_SIGN_ENTITLEMENTS` verbatim into the pbxproj; when spec was at repo root but project at `app/`, the path doubled to `app/app/PocketLens/PocketLens.entitlements`.
- `packages/*` paths in the spec are now `../packages/X` (one level up from `app/`).
- Makefile `gen` target is now `cd app && xcodegen generate`.
- User's environment also needed `xcodebuild -runFirstLaunch` once — resolved a stale CoreSimulator version that was blocking `IDESimulatorFoundation` plugin load.

**Accepted plist changes (made externally during session):**
- `app/PocketLens/Info.plist` — simplified to minimal bundle keys (no category/versioning placeholders). User/tooling decision; left as-is.
- `app/PocketLens/PocketLens.entitlements` — now empty `<dict/>`. App no longer sandboxed. Intentional per system reminder. Phase 6 (folder watching) will need to revisit if sandbox is re-enabled — security-scoped bookmarks would be required for `~/Documents/PocketLens/Inbox`.

**Open items / next action:**
- Phase 1 (v0.1 MVP) is ready to start — see `.claude-plans/02-phase-1-mvp.md` for the pinned "Next Action".
- Four open questions deferred to Phase 1 (Itaú PDF fixture, SQLite lib choice, git init + remote, LICENSE author name).

---

## 2026-04-25 — Phase 1 pivot: LLM-driven extraction + first commit

**Active phase:** 1 — LLM-Powered Statement Import (replanned)
**Goal this session:** Resolve Phase 1 open questions, take the first git commit, and rebuild the Phase 1 plan around an LLM-driven extraction architecture (no per-bank parsers).

**Shipped:**
- LICENSE updated: `Lucas Arcanjo`.
- `.gitignore` fix: removed `Packages/` (legacy SwiftPM dir) — it was matching `packages/` on macOS's case-insensitive FS and silently hiding the SPM packages from git. `.build/` and `.swiftpm/` continue to be ignored.
- First commit `719d7e2` (root) — Phase 0 scaffold landed on `main`. 45 files, no remote.
- Reference fixture: `fixtures/statements/itau-personnalite-2026-03-private.pdf` (Itaú Personnalité Mastercard Black, multi-card statement). Gitignored via `*-private.pdf`.
- **Full plan rebuild around LLM extraction:**
  - `.claude-plans/02-phase-1-mvp.md` — rewritten. New flow: PDFKit → Redactor → AnthropicProvider tool-use → ExtractedStatement → ExtractionValidator → MerchantNormalizer → DeduplicationEngine → GRDB persist. New Domain: multi-card with `cards` FK to `accounts`, `purchase_method`, `posted_year_inferred`, international fields, `bank_category_raw`. ImportBatch records LLM provider/model/prompt-version/tokens/cost. Validation against printed per-card and grand totals. MockLLMProvider drives tests; AnthropicProvider integration test is opt-in.
  - `.claude-plans/06-phase-5-llm.md` — slimmed to "expansion": Ollama, OpenAI, categorization assist, monthly summary, rule suggestions, cost dashboard. The provider abstraction + Anthropic + redaction + Keychain + first-launch disclosure already ship in Phase 1.
  - `.claude-plans/00-OVERVIEW.md` — updated decisions list (GRDB locked, LLM extraction architecture, LLM-only posture with inline drop-zone disclosure, license author).
  - `docs/llm-integration.md` — rewritten as the hub doc. Full `ExtractedStatement` JSON schema, AnthropicProvider specifics (prompt caching, tool-use, retries, pricing), prompt outline, privacy contract, opt-in integration tests.
  - `docs/privacy.md` — rewritten. Honest about cloud LLM in v0.1; redaction details; sandbox-disabled note; per-feature mode planning for Phase 5.
  - `docs/parsers.md` — rewritten as "Statement Extraction". No per-bank Swift classes; new issuers are fixtures + optional prompt addenda.
  - `docs/import-flow.md` — full redraw of the lifecycle around the LLM step + validation + sections-to-exclude.
  - `docs/architecture.md` — mermaid + dependency direction updated; LLM is on the import critical path.
  - `docs/data-model.md` — schema v1 redesigned: cards FK accounts, ImportBatch carries statement totals + LLM provenance, transactions carry `original_amount/fx_rate/purchase_method/bank_category_raw/fingerprint(unique)`, fingerprint is SHA-1 hex stored in a TEXT column.
  - `docs/categorization.md` — added Bank-category-mapping as priority 4 (before keyword rules); confidence band 0.85.

**Decisions made:**
- **GRDB.swift v6.x** — locked persistence library.
- **LLM-driven extraction** — no per-bank parsers. AnthropicProvider in Phase 1 with tool-use + prompt caching; default model `claude-sonnet-4-6`, alternate `claude-opus-4-7`.
- **Privacy posture honest update.** v0.1 is NOT fully local-first because extraction depends on cloud LLM. Disclosure is structural and inline, not modal: a one-liner on first-launch onboarding (next to the API-key paste field) and a one-liner on the drop zone itself ("By uploading, you agree to send the redacted text to Anthropic Claude — not used for training"). Uploading the file IS the consent act. **There is no non-LLM mode and no manual-entry fallback** — if a user doesn't want their statement text sent to an LLM, this app isn't for them. Phase 5 adds Ollama as the local alternative for privacy-sensitive users; the drop-zone disclosure updates to match the active provider.
- **Pre-LLM redaction** strips full card numbers (last-4 retained), CPF/CNPJ, and street addresses. Holder names + cities pass through.
- **Validation is mandatory.** Per-card and grand totals from the PDF must match extracted sums within R$0.01. Mismatches mark `validation_status = warning`, never silent acceptance.
- **Roll our own Anthropic HTTP client** — not pulling in a community Swift SDK. Surface is one POST.
- **No SDK for Ollama either** — same reasoning, deferred to Phase 5.
- **License author** — Lucas Arcanjo.
- **Repo init** — already done by user; not pushed to a remote.

**Open items / next action:**
- User to confirm the rebuilt Phase 1 plan before any code lands.
- Implementation order (per the plan's Next Action): Domain (Money + enums + entities) → ExtractedStatement DTO + MockLLMProvider + ExtractionPromptV1 → PDFTextExtractor → ExtractionValidator → end-to-end fixture test → AnthropicProvider → Persistence + repos → app UI.

---

## 2026-04-25 — Phase 1 implementation: backend + UI scaffold

**Active phase:** 1 — LLM-Powered Statement Import
**Goal this session:** Implement the entire Phase 1 stack — Domain → LLM (mock + Anthropic) → Importing pipeline → Persistence (GRDB) → SwiftUI app — and get `make test` passing end-to-end.

**Shipped (89 tests passing, 0 failures across 5 packages + app):**
- **Domain** (25 tests) — `Money`/`Currency` (Decimal-backed, currency-safe arithmetic, banker's rounding), `TransactionType`/`PurchaseMethod`/`Installment`/`ValidationStatus`/`LLMProviderKind` enums, `Account`/`Card`/`Merchant`/`Category` value types, `Transaction` with deterministic SHA-1 fingerprint (matches `docs/data-model.md` shape), `ImportBatch` with full LLM provenance, `DefaultCategories` seed data per spec §19.
- **LLM** (27 tests) — `LLMProvider` protocol, `ExtractedStatement` Codable DTO mirroring the JSON tool schema, `ExtractionResult`, `MockLLMProvider` (canned + bundle-resource init), `ExtractionPromptV1` (versioned constant with full system prompt + tool JSON schema, snapshot-tested), `Pricing` table for Sonnet 4.6 / Opus 4.7, `Redactor` (card-number → last4, CPF, CNPJ, BR street addresses; pluggable rules; preserves merchant + city), `KeychainStore` (round-tripped against real Keychain), `AnthropicProvider` (URLSession transport — pluggable for tests; tool-use with strict schema; ephemeral cache_control on system prompt; retries on 429/5xx; usage parsing; cost computation).
- **Importing** (21 tests) — `PDFTextExtractor` (PDFKit, page-by-page; SHA-256 helper for file dedup), `MerchantNormalizer` (casefold + collapse whitespace + strip leading provider prefixes + strip trailing installment markers), `ExtractionValidator` (per-card subtotal vs printed within R$0.01, grand total within R$0.01, orphan card refs, low-confidence threshold), `DeduplicationEngine` (in-memory fingerprint collapse, order-stable), `ImportPipeline` orchestrator → `ImportPlan` with `PendingTransaction`s. End-to-end mock-LLM-driven test against the canned fixture (3 cards, 9 transactions, installment 6/10, AMAZON US international + IOF, virtual_card glyph).
- **Persistence** (15 tests) — `SQLiteStore` (`~/Library/Application Support/PocketLens/pocketlens.db`, WAL + foreign keys), Schema v1 migration covering all 6 tables (categories, accounts, cards, merchants, import_batches, transactions) with FK ordering, indexes per spec, UNIQUE on `transactions.fingerprint` and `import_batches.source_file_sha256`. Records bridging Domain ↔ DB. Repos for every entity. `DefaultDataSeeder` (idempotent). `ImportPersister` — single GRDB write transaction taking an `ImportPlan` → upserts account/cards/merchants → inserts batch → inserts transactions; rejects duplicate file SHA-256 with `alreadyImported(batch:)`; whole-batch rollback if any fingerprint collides cross-batch.
- **App UI** — `AppState` env object (Keychain-backed key, store handle, model picker, reset DB), `OnboardingView` (single-screen disclosure + key paste, refuses to proceed without a key), `MainWindow` (NavigationSplitView, 5 sidebar items), `TransactionsView` (sectioned by card with method icons, installment chips, inline category picker, pt_BR currency formatting, full-area drag-and-drop, `File → Import…` / ⌘O via NotificationCenter), `ImportFlowController` (4-phase progress: extracting → calling Claude → validating → saving; surfaces `alreadyImported` as friendly "batch #N on YYYY-MM-DD" error), `ImportProgressSheet` (phase ticker + warnings disclosure), `ImportsView` (batch list with validation badge + LLM provenance + cost), `CategoriesView` (read-only, hex-color → SwiftUI Color), `SettingsView` (key reveal-on-click + save + forget; model picker; reset-DB with hard confirmation).

**Decisions made:**
- **Fingerprint shape** stays SHA-1 hex of `posted_date|merchant_normalized|amount|currency|card_last4|installment_current|installment_total|purchase_method` per the data-model doc; computable in `Domain` without a DB so tests verify it standalone.
- **Persistence depends on Importing** — `ImportPersister` lives in `Persistence` and consumes the `ImportPlan` produced by Importing. Cleaner than putting the GRDB transaction in the app target.
- **Migration ordering**: `categories` is created first because GRDB's `references()` resolves the target table at migration build time — forward FK declarations error with `foreign_keys = ON`.
- **AnthropicProvider transport is pluggable** — `AnthropicTransport` protocol, default `URLSessionTransport`. Tests inject a `FakeTransport` with queued canned responses, so retries/error paths/request-shape are unit-tested without ever hitting `api.anthropic.com`.
- **Optional cost ceilings deferred** — the plan calls for warn-at-$0.50 / hard-stop at $2.00 per import. Not wired in this pass; cost is computed and stored but not gated. Phase-1 follow-up.
- **Categorization package** is still a placeholder enum — Phase 2's home. Touching only the build cache to make `make test-packages` pass.

**Verification done this session:**
- `swift test` passes for each of `Domain`, `LLM`, `Importing`, `Persistence`, `Categorization` individually.
- `make gen` regenerates the Xcode project cleanly with the new `Views/` and `ViewModels/` subfolders auto-included.
- `xcodebuild ... build` succeeds for the macOS app target.
- `make test` end-to-end: 88 SPM tests + 1 app smoke test all pass.

**NOT verified this session (explicitly):**
- The drag-and-drop drop-zone, `File → Import…` / ⌘O, and `ImportProgressSheet` flows have not been exercised against a real PDF + real Anthropic key. The pipeline code path they wrap is unit-tested via the `MockLLMProvider`, but the macOS-side I/O (file picker, drop hover, sheet present/dismiss, key reveal) is glue that needs a manual smoke test next session.
- The opt-in integration test against `api.anthropic.com` (gated by `POCKETLENS_LLM_INTEGRATION=1`) is in the plan but has not been wired up — `AnthropicProviderTests` covers the request shape + response decoding entirely with the fake transport.

**Open items / next action:**
- Manual smoke test the import flow on the user's machine with the gitignored `fixtures/statements/itau-personnalite-2026-03-private.pdf` and a real Anthropic key. Verify: onboarding key paste → drag-and-drop → progress sheet phases → transactions appear grouped by card → re-importing the same PDF surfaces the friendly "already imported" message.
- Wire the $0.50 warn / $2.00 hard-stop cost ceiling around `AnthropicProvider.extractStatement`.
- Add the opt-in `POCKETLENS_LLM_INTEGRATION` test (one-call sanity check against the real API).
- Once the smoke test passes, mark Phase 1 ✅ in `00-OVERVIEW.md` and unblock Phase 2.

---

## 2026-04-25 — Phase 1 closeout: smoke test passed, Phase 2 unblocked

**Active phase:** 1 → 2 transition
**Goal this session:** Close out Phase 1 after the manual smoke test and flip Phase 2 to ⏭ ready.

**Shipped:**
- Manual smoke test passed end-to-end on the user's machine against the gitignored `fixtures/statements/itau-personnalite-2026-03-private.pdf` with a real Anthropic key. Onboarding key paste, drag-and-drop import, progress sheet phases, transactions grouped by card, and the "already imported" rejection on re-import all behaved as designed.
- `00-OVERVIEW.md` status board: Phase 1 → ✅ done, Phase 2 → ⏭ ready to start.
- `02-phase-1-mvp.md` Open Question #3 (cost ceiling) marked resolved; Next Action replaced with a closeout pointer to Phase 2 and a small "Phase 1 Backlog" section for the one deferred item.

**Decisions made:**
- **Cost ceiling won't ship in-app.** User is enforcing $/import spend limits on the Anthropic API/console side. Cost is still computed and stored per `ImportBatch` for visibility; nothing is gated in code.
- **Opt-in integration test stays deferred.** `POCKETLENS_LLM_INTEGRATION=1` against the live API will not be wired up now. Fake-transport coverage in `AnthropicProviderTests` is enough until we have reason to doubt the live contract.

**Open items / next action:**
- Phase 2 (Local Memory & Rules) is ready to start — see `.claude-plans/03-phase-2-memory.md`. Pinned next action there: schema v2 migration (`merchant_aliases`, `categorization_rules`, `user_corrections`), then build `CategorizationEngine` starting with exact user-correction lookup.

---

## 2026-04-25 — Phase 2 implementation: memory, rules, and review UI

**Active phase:** 2 — Local Memory & Rules
**Goal this session:** Land the entire Phase 2 stack — Domain → Persistence (schema v2) → Categorization engine + strategies → ImportPipeline integration → review/rules UI — and get all DoD boxes ticked with `make test` green end-to-end.

**Shipped (117 SPM tests + 1 app test passing across 5 packages + app):**
- **Plan/docs alignment (pre-implementation).** Phase 2 plan and `docs/categorization.md` disagreed on whether bank-category mapping was a priority slot. Resolved with Option A: aligned plan to docs, added `bank_category_mappings` to schema v2, added `BankCategoryStrategy` to the engine. `bank_name` is nullable so a single seed row can serve as wildcard with issuer-specific rows winning.
- **Domain (6 new types).** `CategorizationReason` enum (8 slots), `MerchantAlias` + `Source`, `CategorizationRule` + `PatternType` + `RuleSource`, `UserCorrection` + `CorrectionType`, `BankCategoryMapping` + `DefaultBankCategoryMappings` (Itaú → PocketLens seed table covering ALIMENTAÇÃO, VEÍCULOS, TURISMO, etc.), `CategorizationSuggestion` value type carrying `categoryId`, `confidence`, `reason`, `explanation`.
- **Persistence (schema v2 + repos + extended seeder).** Append-only migration `v2_phase2_memory_and_rules` adding `merchant_aliases` (UNIQUE on `(merchant_id, alias)`), `categorization_rules` (with `enabled`, `priority`, `created_by`), `user_corrections`, `bank_category_mappings` (UNIQUE on `(bank_name, bank_category_raw)` with NULL-as-wildcard semantics). Records and async repos for each. `DefaultDataSeeder` extended to populate `bank_category_mappings` from `DefaultBankCategoryMappings.all` after categories are seeded — short-circuits on non-empty target table so re-running is idempotent. `TransactionRepository` got `updateCategorization`, `find(id:)`, `findByFingerprint(_:)`, `categorized()`. `MerchantRepository` got `setDefaultCategory(merchantId:categoryId:)` so the alias editor can adopt a transaction's category as the merchant's default without touching GRDB from the app target.
- **Categorization engine (10 new files).** `CategorizationStrategy` protocol + `CategorizationInput` DTO. Eight strategies in priority order: `UserCorrectionStrategy` (fp lookup, conf 1.00), `MerchantAliasStrategy` (longest-alias-first substring match → `defaultCategoryId`, conf 0.95), `RuleStrategy` (parameterized for slots 3 + 5; matchers for `.contains` / `.exact` / `.regex` (case-insensitive, malformed-regex falls through) / `.merchant` (id equality) / `.amountRange` (`min..max` in minor units, `*` for unbounded), confs 0.90 / 0.80), `BankCategoryStrategy` (issuer-specific beats wildcard, conf 0.85), `SimilarityStrategy` (Jaccard over character bigrams, threshold 0.85, scaled into 0.50–0.85 band), `LLMSuggestionStrategy` (Phase-5 stub returning nil). `CategorizationEngine.standard(store:)` wires the production order. `CategorizationEngine.apply(to:bankName:)` walks an `ImportPlan` and returns a new plan with each transaction's `categoryId` / `confidence` / `categorizationReason` populated — the integration seam between the engine and `ImportPipeline.dryRun(...)`.
- **Importing/Persistence wiring.** `ImportFlowController` now calls `dryRun → engine.apply → persist`, with a new `categorizing` phase between `validating` and `saving` rendered in `ImportProgressSheet`. Categorization runs after dryRun (reads existing DB state) and before persist (writes the categorized rows in one GRDB transaction). Categorization package gained an `Importing` dep (Importing → Domain/LLM, Persistence → Importing, Categorization → Persistence/Importing — no cycle).
- **App UI.** New sidebar entries: **Review** and **Rules**. `CategorizationReasonBadge` renders below each transaction row with reason-keyed icon + tint + confidence percent; reason key is recovered heuristically from the explanation prefix (cheap inference, deferred adding a `categorization_reason_key` column to schema). `TransactionsViewModel.updateCategory(...)` now writes a `UserCorrection` row when the assignment changes — closing the memory loop. Right-click on any transaction row exposes "Create rule from this transaction…" and "Add merchant alias…" actions wired to two new sheets. `RuleEditorView` (full CRUD form: pattern type + pattern + category + name + priority + enabled, with pre-fill from a transaction). `MerchantAliasEditorView` (alias text + anchor merchant; on save it inserts the alias and sets the merchant's `defaultCategoryId` to the transaction's category so the alias has something to assign on next import). `RulesListView` lists user vs system rules with edit/delete (system rules read-only). `ReviewView` filters by uncategorized / low-confidence (<0.50) / needs-review (0.50–0.79) / all-flagged, sorted by confidence ascending.
- **Tests.** Persistence: schema v2 tables present, 7 new repo tests covering UNIQUE constraints, priority ordering, source filtering, disabled exclusion, issuer-specific-beats-wildcard at the repo, seeder default-population + idempotency. Categorization: 5 RuleStrategy tests (one per `PatternType` + malformed regex falls through + priority desc), 2 MerchantAliasStrategy tests (variant collapse, no-default-category fallthrough), 5 BankCategoryStrategy tests (case-insensitivity, wildcard fallback, issuer-specific tiebreak), 3 UserCorrectionStrategy tests, 4 SimilarityStrategy tests (identical / near match / below threshold / empty corpus), 5 EnginePriorityTests (slot-vs-slot tiebreaks, uncategorized fallthrough, confidence-band assertions across all strategies), 1 ImportPlanCategorizationTests covering `engine.apply(to:bankName:)` end-to-end against a built plan. Total: 29 categorization tests + 25 persistence tests, 117 SPM-level + 1 app-target test all green.

**Decisions made:**
- **Bank-category-mapping promoted to slot 4 (Option A from earlier this session).** Plan and docs both updated. Itaú statements already carry `bank_category_raw` for free, so this is the cheapest "right out of the gate" categorization win we have before any user rules exist. `bank_name = NULL` rows act as wildcards; issuer-specific rows beat them at lookup time. `bank_category_raw` is stored casefolded so matching is plain equality.
- **Strategies own their persistence queries**, no separate `CategorizationMemory` facade. Each strategy takes a `SQLiteStore` and queries the repos it needs. Simpler than a fat protocol, and tests inject an in-memory store directly. Updated the plan task to reflect this.
- **CategorizationReason isn't persisted as a column.** The free-text `categorization_reason` field stores the human-readable explanation; the structured key is inferred at render time by `CategorizationReasonBadge.reason(forExplanation:confidence:)` from the explanation prefix. Heuristic, but stable as long as the engine's explanation phrases stay stable. Added an entry to the Phase-2 backlog to add a `categorization_reason_key` column when it bites us.
- **Categorization runs between dryRun and persist, not inside persist.** Engine queries open their own GRDB read transactions, so they can't safely run inside a write transaction without deadlock. Net effect: categorization sees a consistent snapshot, then a single write block lands the new rows.
- **User-correction matching is fingerprint-only in Phase 2.** Slot 1 (`UserCorrectionStrategy`) compares against a prior transaction with the *same* fingerprint, which only fires on overlapping re-imports. Cross-statement learning (correct January's PADARIA REAL → applies to February's recurring) is deferred to Phase 4, where bank-statement linkage will introduce a softer match key. Documented in the Phase-2 backlog.
- **Bulk category assignment deferred.** DoD covered by the single-row picker; revisit if the review queue gets long enough to feel painful.
- **Phase 1's `confidence` field doubles as Phase 2's categorization confidence.** Phase 1 was using it for LLM-extraction confidence (placeholder until Phase 2 took over), and the engine now overwrites it with the strategy's confidence band. Single field, two phases — documented in the categorization apply step.

**Open items / next action:**
- Manual smoke test on the user's machine against `fixtures/statements/itau-personnalite-2026-03-private.pdf` (gitignored). Verify: the categorizing phase appears in the progress sheet; transactions land with reason badges populated; bank-category-mapping fires on Itaú labels (e.g. "VEÍCULOS" → Transporte at conf 0.85); right-click "Create rule" opens the editor pre-filled with the merchant_normalized; saving a rule and re-running the import causes that rule to win against the bank-mapping; review queue shows uncategorized rows.
- After smoke test passes, mark Phase 2 ✅ in `00-OVERVIEW.md` and unblock Phase 3.

---

## 2026-04-25 — Phase 2 closeout: smoke test passed, Phase 3 unblocked

**Active phase:** 2 → 3 transition
**Goal this session:** Close out Phase 2 after the manual smoke test and flip Phase 3 to ⏭ ready.

**Shipped:**
- Manual smoke test of the Phase 2 stack passed end-to-end on the user's machine against the gitignored `fixtures/statements/itau-personnalite-2026-03-private.pdf`. Categorizing phase shows in the progress sheet, reason badges render, bank-category-mapping fires on Itaú labels, "Create rule from this transaction" pre-fills and persists, review queue surfaces uncategorized rows, and a saved user rule wins over the bank-mapping on re-import.
- `00-OVERVIEW.md` status board: Phase 2 → ✅ done, Phase 3 → ⏭ ready to start.
- `03-phase-2-memory.md` Next Action replaced with a closeout pointer to Phase 3.

**Open items / next action:**
- Phase 2 implementation is currently uncommitted on `main` — see `git status` (Domain + Persistence + Categorization + app/Views diffs plus the modified `docs/data-model.md`). Take the Phase 2 commit before starting Phase 3.
- Phase 3 (Dashboard, v0.3) is ready — see `.claude-plans/04-phase-3-dashboard.md` for the pinned next action.

---

## 2026-04-26 — Phase 3 implementation: dashboard backend + UI

**Active phase:** 3 — Dashboard
**Goal this session:** Land the entire Phase 3 stack — aggregate SQL queries in Persistence → DashboardViewModel → SwiftUI dashboard with charts → wire as default landing tab — and get `make test` green end-to-end.

**Shipped (137 tests passing — 136 SPM + 1 app smoke):**
- **Persistence — `AggregateQueries` (9 new tests).** Single struct with raw-SQL methods, all `GROUP BY` happens in SQLite. Half-open date semantics (`posted_date >= start AND posted_date < endExclusive`) — documented at the API. "Spending" excludes `payment` and includes `purchase`/`refund`/`fee`/`iof`/`adjustment`; refunds (negative amounts) offset purchases inside `SUM`. `largestTransactions` additionally requires `amount > 0` so refunds don't show as "largest". Methods: `totalsByCurrency`, `spendingByCategory` (LEFT JOIN to categories — uncategorized rows collapse to a single bucket), `topMerchants` (GROUP BY `merchant_normalized` for stability), `largestTransactions` (JOIN cards), `uncategorizedCount`, `needsReviewCount` (default band 0.50–0.80, matches Phase 2's `ReviewView`), `totalsByCard`. Tests cover month boundaries (start inclusive / end exclusive verified with rows at exactly 2026-03-01 and 2026-04-01), mixed currency, refund offsets, payment exclusion, and empty periods.
- **`DashboardViewModel`.** `@MainActor ObservableObject` mirroring `TransactionsViewModel` style. Owns `DashboardDateRangePreset` (`thisMonth` / `lastMonth` / `last3Months` / `custom`) + custom date pair + `selectedCurrency`, all persisted via `@AppStorage`. `interval(now:)` builds boundaries in UTC so they line up with the UTC-formatted `posted_date` strings on disk. `reload(store:)` issues queries in parallel via `async let`, auto-selects the highest-spending currency on first load when the persisted choice has no data in the period.
- **Dashboard SwiftUI views (`Views/Dashboard/`).** `DashboardView` composes everything in a `ScrollView` with `ViewThatFits` for two-column-on-wide / stacked-on-narrow responsive layout. Sub-views in their own files: `DateRangePicker` (segmented + DatePickers when custom), `SpendingByCategoryChart` (Swift Charts `SectorMark` pie + ranked legend, `ViewThatFits` again for tight panes), `TopMerchantsChart` (horizontal `BarMark` with trailing-annotation totals), `LargestTransactionsList`, `NeedsAttentionCards` (two click-through tiles), `CreditCardTotalsCard`. `DashboardCard` + `EmptyDashboardSection` are shared chrome. `DashboardFormatters` centralizes currency formatting (pt-BR for BRL, en-US for USD, de-DE for EUR, en-GB for GBP — exhaustive Currency switch caught by the compiler on first build) and the hex-to-`Color` helper.
- **MainWindow wiring.** Default sidebar selection flipped from `.transactions` to `.dashboard`. `DashboardPlaceholderView` deleted (no longer needed). `MainWindow` now holds `reviewInitialFilter` + `reviewSessionId` (UUID); the dashboard's attention cards call back into it to set the filter, bump the session id, and flip the selection. `ReviewView.id(reviewSessionId)` forces SwiftUI to re-init the view's `@State filter` from the new `initialFilter` arg on each navigation event.
- **`ReviewView` API change.** Added `init(initialFilter: Filter = .all)`. Backwards-compatible default — existing call sites elsewhere keep working.

**Decisions made:**
- **"Spending" definition is shared between aggregate queries.** `('purchase','refund','fee','iof','adjustment')` — payments are explicitly excluded across all dashboard queries so the user-pays-card transaction never inflates totals or shows up as "uncategorized". Refunds stay in the SUM so the period total reflects net spend; `largestTransactions` adds an `amount > 0` filter so refunds don't visually dominate.
- **Half-open date intervals.** API takes `start: Date, endExclusive: Date` instead of `DateInterval` to dodge Apple's inclusive-end ambiguity. `DashboardViewModel.interval()` builds month boundaries via `Calendar` configured with UTC so they round-trip cleanly with the UTC `posted_date` strings on disk. Custom-range end-date is bumped forward by one day in the view model so the user-picked end date is *included* in the result set.
- **Per-card-only on the credit-card card.** Plan's Open Question (Person-level grouping) is deferred — semantics undefined. Card-only ships in v0.3; the deferral is captured in the Phase 3 Backlog section of the plan file.
- **Currency switcher only renders when ≥2 currencies are present in the period.** Avoids visual noise for the common BRL-only case. The breakdowns (categories / merchants / cards / largest) are scoped to one currency; the totals card lists every currency on its own line.
- **Snapshot tests skipped.** Plan called them out as optional ("if we use swift-snapshot-testing"). Swift Charts output is hard to snapshot reliably and the underlying data is already covered by `AggregateQueriesTests`. Captured in Phase 3 Backlog.
- **Categorization-reason inference still lives in the row badge** — Phase 3 didn't introduce a `categorization_reason_key` column. Phase 2 backlog item still applies.
- **Dashboard reload trigger** — `.task` on first appear plus `.onChange(of: app.store?.queue.path)` to reload after a DB reset. Not auto-reloaded after an import; user can trigger it by switching tabs. Acceptable for v0.3 (imports are infrequent and explicit).

**Verification done this session:**
- `swift test` passes for each of `Domain` (25), `Persistence` (34, +9 new aggregate tests), `Importing` (21), `Categorization` (29), `LLM` (27).
- `make gen` regenerates the Xcode project cleanly with the new `Views/Dashboard/` folder auto-included (no `project.yml` edit needed — the existing `path: PocketLens` rule recurses).
- `make test` end-to-end: 136 SPM + 1 app smoke = 137 tests, 0 failures.

**NOT verified this session (explicitly):**
- The dashboard has not been exercised against a real PDF + real data on the user's machine. Visual layout (responsive columns, pie chart, horizontal bar chart, click-through navigation, custom date range picker) is glue that needs a manual smoke test next session.
- Auto-refresh after import is not wired — a successful import doesn't poke the dashboard. User must switch tabs or change the date range to re-query. Captured in the implicit follow-up.

**Open items / next action:**
- Manual smoke test the dashboard on the user's machine. Verify: Dashboard is the default landing tab; date-range presets re-issue queries; pie + ranked bars match seeded categories; "Uncategorized" / "Needs review" counts navigate to `ReviewView` with the correct filter pre-selected; per-card totals reflect the multi-card statement; mixed-currency view (if applicable) shows the currency switcher.
- After smoke test passes, mark Phase 3 ✅ in `00-OVERVIEW.md` and unblock Phase 4.

---

## 2026-04-26 — Phase 3 closeout: smoke test passed, Phase 4 unblocked

**Active phase:** 3 → 4 transition
**Goal this session:** Close out Phase 3 after the manual smoke test and flip Phase 4 to ⏭ ready.

**Shipped:**
- Manual smoke test of the Phase 3 dashboard passed end-to-end on the user's machine. Dashboard lands as the default tab, date-range presets re-issue queries, pie + ranked bars match seeded categories, attention cards navigate to `ReviewView` with the right filter pre-selected, per-card totals reflect the multi-card statement.
- `00-OVERVIEW.md` status board: Phase 3 → ✅ done, Phase 4 → ⏭ ready to start.
- `04-phase-3-dashboard.md` Next Action replaced with a closeout pointer to Phase 4.

**Decisions made (intentional, post-implementation edit landed in `AggregateQueries.swift`):**
- **Bucketing switched from `posted_date` to `COALESCE(b.statement_period_end, t.posted_date)`.** All dashboard aggregations now bucket transactions by the close date of the statement they appeared on, falling back to `posted_date` when statement metadata is missing. This makes installments land in the month they're being charged, not the original purchase month — the natural mental model for credit-card spending. Required adding a `JOIN import_batches b ON b.id = t.import_batch_id` to every aggregation query.

**Open items / next action:**
- Phase 4 (Bank Statement Import, v0.4) is ready to start — see `.claude-plans/05-phase-4-bank.md` for its pinned next action.
