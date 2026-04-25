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
