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
