# Import Flow

This document describes the life of a single file dropped into PocketLens.

## Lifecycle

```
User drops file → PDFImporter/CSVImporter/OFXImporter
       │
       ▼
  File-hash dedup → already seen? stop with friendly message
       │
       ▼
  Create ImportBatch (status: pending)
       │
       ▼
  Select parser (by format + content sniff)
       │
       ▼
  Parse → ParsedStatement + ParserDiagnostics
       │
       ▼
  Normalize each transaction (TransactionNormalizer)
       │
       ▼
  Transaction-fingerprint dedup → skip duplicates
       │
       ▼
  Categorize each new transaction (CategorizationEngine)
       │
       ▼
  Write transactions + mark ImportBatch completed
       │
       ▼
  UI refreshes, review sheet surfaces low-confidence items
```

## File-Level Deduplication

Every imported file's SHA-256 hash is stored on `import_batches.file_hash` with a unique constraint. Re-importing the same file is a no-op with a clear user-facing message.

Hashing happens on raw bytes, so even a single-byte difference (e.g., re-downloaded file with different metadata) produces a new hash and a new import. Transaction-level dedup catches overlap in that case.

## Transaction-Level Deduplication

Each new transaction is fingerprinted:

```
date | description_normalized | amount | card_last_digits | installment_current | installment_total | source_type
```

A unique index on this tuple in `transactions` enforces uniqueness at the DB level. Duplicates are detected **before** insert and counted in diagnostics rather than raising errors.

**Edge case:** two transactions with identical everything except they really are two separate charges (e.g., two identical coffee purchases on the same day). The fingerprint collision suppresses one. We accept this as a minor false-positive risk in exchange for simple, robust dedup on re-import.

## Normalization Rules

The `TransactionNormalizer` produces `description_normalized` by:

- Stripping leading/trailing whitespace.
- Collapsing internal whitespace to a single space.
- Uppercasing.
- Removing common noise prefixes/suffixes (e.g., `MP *`, `PIX*`, `* PARC N/M`).
- Preserving installment info in structured fields, not in the description.

Normalization is **reversible via stored `description_raw`** — we never lose the original. Rules can be authored against either field but default to normalized.

## Import States

An `ImportBatch` has a `status` column with three values:

- `pending` — created, parse not yet complete.
- `completed` — all transactions written successfully.
- `failed` — parser threw, or DB write failed. Diagnostics explain.

Failed imports don't leave dangling transactions; the whole insert happens in a single transaction and rolls back on error.

## Auto-Import (Phase 6)

The same pipeline runs in two modes:

- **Interactive** — user dropped a file or picked one. Progress + review UI visible.
- **Auto** — watcher detected a file in `~/Documents/PocketLens/Inbox`. Runs in the background, posts a `UNUserNotifications` banner with the summary. Failed files move to `Inbox/failed/` for user inspection.

See [`.claude-plans/07-phase-6-automation.md`](../.claude-plans/07-phase-6-automation.md).

## Error Surfaces

- Parser errors → captured in `ParserDiagnostics` and stored on the batch; surfaced in the Imports list screen with a "View details" affordance.
- Unknown file type → rejected with a clear message before a batch is created.
- DB errors → logged via `os.Logger`; user sees a generic "Import failed" toast with a log-location hint.
