# Data Model

This document is the **authoritative source** for the PocketLens SQLite schema. Migrations in `packages/Persistence/Sources/Persistence/Migrations.swift` MUST match what's here. When they diverge, update this doc in the same PR.

## Conventions

- All tables use integer `id` primary keys.
- Timestamps are ISO-8601 strings (UTC) for portability.
- Monetary amounts are stored in the smallest currency unit as `INTEGER` (e.g., centavos, cents). The `Money` value type in `Domain` handles conversion.
- `currency` is ISO 4217 (`BRL`, `USD`, …).
- Foreign keys are enforced (`PRAGMA foreign_keys = ON`).
- WAL journal mode (`PRAGMA journal_mode = WAL`).

## Schema v1 (Phase 1 — LLM-Powered Statement Import)

### `accounts`

A bank-relationship-level entity (one bank, one holder).

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `bank_name` | TEXT | e.g., `Itaú Personnalité` |
| `holder_name` | TEXT | Primary holder for this relationship |
| `account_alias` | TEXT NULL | User-set nickname |
| `created_at` / `updated_at` | TEXT | |

### `cards`

A physical/virtual credit card. A statement may contain multiple cards under the same `account_id`, each with a different holder.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `account_id` | INTEGER | FK → `accounts.id` |
| `last4` | TEXT | Last 4 digits |
| `holder_name` | TEXT | The cardholder named on the statement section |
| `network` | TEXT NULL | `Mastercard` / `Visa` / `Amex` / `Elo` / … |
| `tier` | TEXT NULL | `Black` / `Gold` / … |
| `nickname` | TEXT NULL | User-set |
| `created_at` / `updated_at` | TEXT | |

**Unique:** `(account_id, last4)`.

### `merchants`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `raw` | TEXT | First-seen raw string (kept for reference) |
| `normalized` | TEXT | After `MerchantNormalizer` — **unique** |
| `default_category_id` | INTEGER NULL | FK → `categories.id` (Phase 2 populates) |
| `created_at` / `updated_at` | TEXT | |

### `categories`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `name` | TEXT | |
| `parent_id` | INTEGER NULL | FK → `categories.id` for sub-categories |
| `color` | TEXT NULL | Hex |
| `icon` | TEXT NULL | SF Symbol name |
| `created_at` / `updated_at` | TEXT | |

Seeded on first run with the default set per spec §19.

### `import_batches`

One row per file the user imports.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `source_file_name` | TEXT | Original filename |
| `source_file_sha256` | TEXT | SHA-256 of raw bytes — **unique** |
| `source_pages` | INTEGER | Page count |
| `statement_period_start` | TEXT NULL | |
| `statement_period_end` | TEXT NULL | Closing date |
| `statement_close_date` | TEXT NULL | Same as `period_end`, kept distinct for clarity |
| `statement_due_date` | TEXT NULL | |
| `statement_total` | INTEGER | In smallest unit; matches "Total dos lançamentos atuais" |
| `previous_balance` | INTEGER NULL | |
| `payment_received` | INTEGER NULL | |
| `revolving_balance` | INTEGER NULL | |
| `currency` | TEXT | Statement-level currency (BRL for Itaú) |
| `llm_provider` | TEXT | e.g., `anthropic` / `mock` |
| `llm_model` | TEXT | e.g., `claude-sonnet-4-6` |
| `llm_prompt_version` | TEXT | e.g., `v1` |
| `llm_input_tokens` | INTEGER | |
| `llm_output_tokens` | INTEGER | |
| `llm_cache_read_tokens` | INTEGER NULL | |
| `llm_cost_usd` | REAL | Cents resolution stored as REAL for simplicity |
| `validation_status` | TEXT | `ok` / `warning` / `failed` |
| `parse_warnings` | TEXT NULL | JSON array |
| `status` | TEXT | `pending` / `completed` / `failed` |
| `imported_at` | TEXT | |

**Unique:** `(source_file_sha256)`.

### `transactions`

Core entity. One row per imported transaction.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `import_batch_id` | INTEGER | FK → `import_batches.id` |
| `card_id` | INTEGER | FK → `cards.id` |
| `merchant_id` | INTEGER NULL | FK → `merchants.id` |
| `category_id` | INTEGER NULL | FK → `categories.id` |
| `posted_date` | TEXT | ISO date (year may be inferred) |
| `posted_year_inferred` | INTEGER | 0/1 — true when statement printed only DD/MM |
| `raw_description` | TEXT | As it appears on the statement |
| `merchant_normalized` | TEXT | After `MerchantNormalizer` |
| `merchant_city` | TEXT NULL | From the issuer-provided category line |
| `bank_category_raw` | TEXT NULL | Issuer's own category, e.g. `ALIMENTAÇÃO` — useful as a Phase 2 prior |
| `amount` | INTEGER | In smallest currency unit; positive for purchases, negative for refunds |
| `currency` | TEXT | ISO 4217 |
| `original_amount` | INTEGER NULL | Populated for international transactions (in `original_currency` units) |
| `original_currency` | TEXT NULL | |
| `fx_rate` | REAL NULL | Stored as REAL; `original_amount * fx_rate ≈ amount` |
| `installment_current` | INTEGER NULL | 1 for first of N installments |
| `installment_total` | INTEGER NULL | N |
| `purchase_method` | TEXT | `physical` / `virtual_card` / `digital_wallet` / `recurring` / `unknown` |
| `transaction_type` | TEXT | `purchase` / `refund` / `payment` / `fee` / `iof` / `adjustment` |
| `confidence` | REAL | [0, 1] from the LLM extraction |
| `categorization_reason` | TEXT NULL | Empty in Phase 1; populated in Phase 2 |
| `fingerprint` | TEXT | Computed; **unique** — see below |
| `created_at` / `updated_at` | TEXT | |

**Indexes:**
- `(card_id, posted_date)` — primary read pattern (per-card list, sorted by date).
- `(merchant_id)` for merchant rollups.
- `(category_id)` for category rollups.
- `(import_batch_id)`.
- `UNIQUE(fingerprint)` — transaction-level dedup.

**Fingerprint:**
```
SHA-1( posted_date | merchant_normalized | amount | currency
     | card_last4  | installment_current | installment_total | purchase_method )
```
Stored as a TEXT hex digest. Computed in Domain so it's verifiable in tests without a DB.

## Schema v2 (Phase 2 — Local Memory & Rules)

Adds user-correction memory and rule-based categorization.

### `merchant_aliases`

Map variants ("UBER *TRIP", "UBER TRIP SP") to a canonical merchant.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `merchant_id` | INTEGER | FK |
| `alias` | TEXT | Pattern matched against `merchant_normalized` |
| `source` | TEXT | `user` / `system` / `llm` |
| `created_at` | TEXT | |

### `categorization_rules`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `name` | TEXT | User-friendly label |
| `pattern` | TEXT | The match pattern |
| `pattern_type` | TEXT | `contains` / `regex` / `exact` / `merchant` / `amount_range` |
| `merchant_id` | INTEGER NULL | |
| `category_id` | INTEGER | FK |
| `priority` | INTEGER | Higher wins within the same pattern type |
| `created_by` | TEXT | `user` / `system` / `llm` |
| `enabled` | INTEGER | 0/1 |
| `created_at` / `updated_at` | TEXT | |

### `user_corrections`

Every time a user overrides a category. Drives the top-priority memory match.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `transaction_id` | INTEGER | FK |
| `old_category_id` | INTEGER NULL | |
| `new_category_id` | INTEGER | |
| `correction_type` | TEXT | `category` / `merchant` / `amount` / `date` |
| `note` | TEXT NULL | |
| `created_at` | TEXT | |

### `bank_category_mappings`

Maps an issuer's own category label (`transactions.bank_category_raw`) to a PocketLens category. Drives priority-4 in the categorization chain.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `bank_name` | TEXT NULL | NULL = wildcard (applies to all issuers); issuer-specific row wins over wildcard |
| `bank_category_raw` | TEXT | Casefolded for matching; e.g. `alimentação`, `veículos` |
| `category_id` | INTEGER | FK → `categories.id` |
| `created_at` / `updated_at` | TEXT | |

**Unique:** `(bank_name, bank_category_raw)` — `bank_name = NULL` participates in uniqueness via SQLite's standard NULL handling, which is fine here because we only ever insert one wildcard row per `bank_category_raw`.

Seeded for Itaú on first run. Extending to a new issuer is data, not code.

## Schema v3+ (Later Phases)

- **Phase 4:** A `linked_transaction_id` column on `transactions` (or a small `transaction_links` join table) to connect a bank-side credit-card payment to the corresponding card import batch.
- **Phase 5:** `llm_calls` table for cost tracking; `llm_suggestions` table caching `categorize` results so re-review of the same transaction doesn't re-spend.

Each schema change ships as a versioned migration. Never mutate a shipped migration — always add a new one.
