# Import Flow

This document describes the life of a single statement file dropped into PocketLens.

## Lifecycle (Phase 1: PDF + LLM extraction)

```
User drops file or picks via File → Import…
       │
       ▼
  SHA-256 of raw bytes → file-level dedup
       │ (already in import_batches.source_file_sha256? halt with friendly message)
       ▼
  Create ImportBatch (status: pending)
       │
       ▼
  PDFTextExtractor (PDFKit) — page-by-page text
       │
       ▼
  Redactor — mask CPF/CNPJ, full card number (keep last 4), street address
       │
       ▼
  LLMProvider.extractStatement(text)
       │ (Anthropic tool-use; prompt-cached system + schema; structured output)
       ▼
  ExtractedStatement (Codable DTO)
       │
       ▼
  ExtractionValidator
       │ ├─ per-card subtotal vs printed "Lançamentos no cartão (final XXXX)" ± R$0.01
       │ ├─ grand total vs printed "Total dos lançamentos atuais" ± R$0.01
       │ ├─ international total vs printed "Total lançamentos inter."
       │ └─ confidence floor (warn if >2% of transactions < 0.7)
       ▼ (mismatches → batch.validation_status = warning, captured in parse_warnings)
  MerchantNormalizer (whitespace, casefold, strip installment marker)
       │
       ▼
  DeduplicationEngine — transaction fingerprint
       │ (skip duplicates, count them in diagnostics)
       ▼
  Persist in one GRDB write transaction:
    ImportBatch (status → completed) + Cards (upsert) + Merchants (upsert) + Transactions
       │
       ▼
  UI: Transactions table refreshes; ImportProgressSheet dismisses to results screen
```

## File-level deduplication

SHA-256 of the raw file bytes is stored on `import_batches.source_file_sha256` with a unique constraint. Re-importing the same file is a no-op with a clear "already imported as batch #N on YYYY-MM-DD" message.

A single byte change (re-downloaded PDF with different metadata) produces a new hash and proceeds — transaction-level dedup catches the overlap.

## Transaction-level deduplication

Each new transaction is fingerprinted:

```
posted_date | merchant_normalized | amount | currency | card_last4
            | installment_current | installment_total | purchase_method
```

A unique index on this tuple in `transactions` enforces uniqueness at the DB level. Duplicates are detected before insert and counted in diagnostics (not raised as errors).

**Edge case:** two genuinely separate identical charges on the same day (two coffees, same merchant, same amount) collapse into one. We accept this as a small false-positive risk in exchange for robust re-import. The user can split the row manually if it matters.

## Validation, not silent acceptance

The PDF prints its own totals. We use them. Per-card sums must match `Lançamentos no cartão (final XXXX)` within R$0.01 — and the grand sum must match `Total dos lançamentos atuais`. Drift triggers `validation_status = warning` with a specific message. The import is still saved (the user may want to fix it manually) but it's flagged in the Imports list.

This is the safety net that makes LLM extraction trustable: even if a model hallucinates or skips a line, the printed totals catch it.

## Sections that must be excluded

The Itaú reference statement contains several sections the LLM is explicitly instructed to skip:

- **"Compras parceladas - próximas faturas"** — installments scheduled for FUTURE statements. They aren't real transactions for this batch.
- **"Simulação de Compras parc. c/ juros e Crediário"** — simulation tables. Marketing.
- **"Simulação Saque Cash"** — same.
- **Header summary boxes** ("Resumo da fatura", "Total a pagar") — these are aggregate views of the same transactions, not new ones.

The prompt enumerates these and the model is instructed to ignore them. Validation against printed totals is the backstop if it forgets.

## Normalization rules

`MerchantNormalizer` produces `merchant_normalized` by:

- Stripping leading/trailing whitespace.
- Collapsing internal whitespace.
- Casefolding.
- Removing common provider prefixes/suffixes (`MP *`, `IFD*`, `PIX*`, trailing `\d{1,2}/\d{1,2}`).

The `raw_description` is preserved unchanged — rules can match against either.

## Import states

`ImportBatch.status`:

- `pending` — created, extraction in progress.
- `completed` — all transactions written; `validation_status` separately tracks `ok | warning | failed`.
- `failed` — extraction or DB write threw; whole insert rolled back; diagnostics explain.

## Auto-import (Phase 6)

Same pipeline runs in two modes:

- **Interactive** — user dropped a file or picked one. Progress + review UI visible.
- **Auto** — `FolderWatcher` (FSEvents) detected a file in `~/Documents/PocketLens/Inbox`. Runs in the background, posts a `UNUserNotifications` banner with the summary. Failed files move to `Inbox/failed/` for inspection.

Auto-import requires the LLM provider already configured (Cloud LLM with a Keychain key, or Local LLM with a reachable Ollama endpoint). Both paths run without per-import gates — disclosure happened at first-launch onboarding.

## CSV / OFX (Phase 4)

CSV and OFX files bypass the LLM entirely — they are already structured. `CSVImporter` and `OFXImporter` produce `Transaction` rows directly. The dedup, normalize, persist steps are identical.

## Error surfaces

- LLM provider error (network, schema invalid) → `ImportError` with provider message; batch marked `failed`.
- Validation mismatch → batch saved as `completed` with `validation_status = warning`; user notified.
- DB error → logged via `os.Logger`; whole batch transaction rolls back.
