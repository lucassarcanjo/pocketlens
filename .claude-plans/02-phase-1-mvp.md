# Phase 1 — MVP Import (v0.1)

## Goal
A user can drag a credit card PDF statement into PocketLens and see parsed transactions in a table, edit their categories, and have that work persist locally in SQLite.

## Definition of Done (per spec §21)
- [ ] User can open the macOS app.
- [ ] User can import a credit card statement PDF via drag-and-drop AND file picker.
- [ ] Extracted transactions appear in a sortable table.
- [ ] User can assign or correct a transaction's category.
- [ ] Re-importing the same (or overlapping) statement does NOT create duplicates.
- [ ] Import history is visible and lists every `ImportBatch` with parser diagnostics.
- [ ] All data persists to a local SQLite file on app restart.
- [ ] Default categories from spec §19 are seeded on first run.

## Tasks

### Domain package
- [ ] Implement core entities as Swift types per spec §12:
  - [ ] `Transaction` (all fields from §12.1, incl. `installment_current`/`installment_total`, `confidence`, `categorization_reason`)
  - [ ] `ImportBatch` (§12.2)
  - [ ] `Merchant` (§12.3, aliases deferred to Phase 2)
  - [ ] `Category` (§12.5, with parent_id, color, icon)
  - [ ] `Account` + `Card` (§12.8)
- [ ] `Money` value type in `Shared` submodule (spec §7) — decimal-safe, currency-aware.
- [ ] `TransactionType` enum: `debit | credit | payment | transfer | fee | refund`.
- [ ] `SourceType` enum: `creditCardStatement | bankStatement`.

### Persistence package
- [ ] Decide: GRDB.swift vs SQLite.swift (open question from Phase 0).
- [ ] `SQLiteStore` — opens/creates DB file at `~/Library/Application Support/PocketLens/pocketlens.db`.
- [ ] Schema v1 migration — all tables from §12.1, §12.2, §12.3, §12.5, §12.8 (others deferred to Phase 2).
- [ ] Repositories: `TransactionRepository`, `ImportBatchRepository`, `CategoryRepository`, `MerchantRepository`, `AccountRepository`.
- [ ] Default-category seeder (§19: Groceries, Restaurants, Delivery, Transportation, Fuel, Travel, Health, Pharmacy, Subscriptions, Software, Education, Clothing, Gifts, Home, Utilities, Insurance, Taxes and Fees, Income, Transfers, Credit Card Payment, Uncategorized).

### Importing package
- [ ] `PDFImporter` — takes a file URL, extracts text via PDFKit, produces a `ParsedStatement` DTO.
- [ ] `ItauInvoiceParser` — first real parser. **Requires a sample PDF fixture.**
- [ ] `TransactionNormalizer` — collapses whitespace, strips noise, produces `description_normalized`.
- [ ] `DeduplicationEngine`:
  - File-level: SHA-256 of the raw file → skip import if hash already in `import_batches`.
  - Transaction-level: fingerprint = `date|description_normalized|amount|card_last_digits|installment_current|installment_total|source_type`.
- [ ] `ParserDiagnostics` — counts (found/imported/duplicates/failed), warnings, unrecognized sections (§15.2).

### App target (SwiftUI)
- [ ] Main window with sidebar navigation: Dashboard, Transactions, Imports, Categories, Settings.
  - Only Transactions + Imports + Categories fully wired this phase. Dashboard placeholder until Phase 3.
- [ ] Drag-and-drop drop zone on the Transactions screen.
- [ ] File picker via `FileImporter` sheet.
- [ ] Import-progress + results sheet showing diagnostics.
- [ ] Transaction table using `Table` — columns: date, description, amount, category (editable), card, installments, confidence.
- [ ] Inline category picker (menu button) that writes to SQLite.
- [ ] Imports list screen.
- [ ] Categories list screen (read-only this phase; CRUD in Phase 2).

## Files Touched (anticipated)
- `packages/Domain/Sources/Domain/*.swift` — entities, enums, `Money`.
- `packages/Persistence/Sources/Persistence/{SQLiteStore,Migrations,Repositories,Seeder}.swift`.
- `packages/Importing/Sources/Importing/{PDFImporter,ItauInvoiceParser,TransactionNormalizer,DeduplicationEngine,ParserDiagnostics}.swift`.
- `app/PocketLens/Views/{MainWindow,TransactionsView,ImportsView,CategoriesView,DashboardPlaceholder}.swift`.
- `app/PocketLens/ViewModels/{TransactionsViewModel,ImportsViewModel}.swift`.
- `app/project.yml` — add new SPM package deps if needed (GRDB/SQLite.swift).

## Dependencies
- Requires Phase 0 ✅ (buildable scaffold with all 5 SPM packages wired into the app).

## Test Coverage
- **Parser fixture tests** — `fixtures/statements/itau-<date>.pdf` paired with `fixtures/expected-output/itau-<date>.json` listing expected transactions. `ItauInvoiceParserTests` asserts parsed output matches fixture.
- **Normalizer tests** — whitespace/punctuation/case edge cases.
- **Dedup tests** — same-file re-import, overlapping statements, near-duplicate transactions.
- **Schema migration tests** — open fresh DB, confirm all tables exist with expected columns.
- **Repository tests** — CRUD round-trip per entity.

## Open Questions
1. **Itaú PDF fixture** — does the user have one? Without it, `ItauInvoiceParser` is just a design sketch. If not, consider starting with a simpler bank or a synthetic fixture.
2. **SQLite library choice** — recommend GRDB.swift (richer observation, migration support) unless user prefers SQLite.swift's lighter footprint.
3. **Transaction table library** — built-in SwiftUI `Table` is sufficient for MVP; revisit if performance is a problem at 10K+ rows.
4. **Currency handling** — statements may mix BRL, USD (international transactions + IOF per §15.1). MVP stores currency per-transaction; UI displays natively; no FX conversion.

## Next Action
Confirm Phase 0 verification passed. Then answer open question #1 (Itaú PDF fixture). Start with the `Domain` package — define `Transaction`, `Money`, and enums — because it unblocks everything else.
