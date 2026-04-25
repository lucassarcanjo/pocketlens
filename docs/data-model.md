# Data Model

This document is the **authoritative source** for the PocketLens SQLite schema. Migrations in `packages/Persistence/Sources/Persistence/Migrations.swift` MUST match what's here. When they diverge, update this doc in the same PR.

## Conventions

- All tables use integer `id` primary keys.
- Timestamps are ISO-8601 strings (UTC) for portability.
- Monetary amounts are stored in the smallest currency unit as `INTEGER` (e.g., cents). The `Money` value type in `Domain` handles conversion.
- `currency` is ISO 4217 (BRL, USD, etc.).
- Foreign keys are enforced (`PRAGMA foreign_keys = ON`).

## Schema v1 (Phase 1 — MVP)

### `transactions`

Core entity. One row per imported transaction.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `source_id` | INTEGER | FK to `import_batches.id` |
| `source_type` | TEXT | `credit_card_statement` \| `bank_statement` |
| `date` | TEXT | Transaction date (ISO-8601 date) |
| `posted_date` | TEXT NULL | Posting date if different |
| `description_raw` | TEXT | As it appears on the statement |
| `description_normalized` | TEXT | After `TransactionNormalizer` |
| `amount` | INTEGER | In smallest currency unit; negative = debit from user's POV on bank side |
| `currency` | TEXT | ISO 4217 |
| `transaction_type` | TEXT | `debit` \| `credit` \| `payment` \| `transfer` \| `fee` \| `refund` |
| `installment_current` | INTEGER NULL | 1 for first of N installments |
| `installment_total` | INTEGER NULL | N |
| `card_last_digits` | TEXT NULL | Last 4 digits, if card transaction |
| `account_id` | INTEGER NULL | FK to `accounts.id` |
| `person` | TEXT NULL | Optional — who made the charge |
| `merchant_id` | INTEGER NULL | FK to `merchants.id` |
| `category_id` | INTEGER NULL | FK to `categories.id` |
| `confidence` | REAL NULL | [0, 1] — categorization confidence |
| `categorization_reason` | TEXT NULL | Human-readable reason (see `categorization.md`) |
| `created_at` | TEXT | |
| `updated_at` | TEXT | |

**Indexes:** `(date)`, `(merchant_id)`, `(category_id)`, `(source_id)`, unique index on `(date, description_normalized, amount, card_last_digits, installment_current, installment_total, source_type)` — the **transaction fingerprint** used for dedup.

### `import_batches`

One row per file the user imports.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `source_type` | TEXT | `credit_card_statement` \| `bank_statement` |
| `filename` | TEXT | Original filename |
| `file_hash` | TEXT | SHA-256 of the raw file — **unique** |
| `statement_period_start` | TEXT NULL | |
| `statement_period_end` | TEXT NULL | |
| `imported_at` | TEXT | |
| `parser_name` | TEXT | e.g., `ItauInvoiceParser` |
| `parser_version` | TEXT | For repro and debugging |
| `status` | TEXT | `pending` \| `completed` \| `failed` |
| `diagnostics` | TEXT NULL | JSON blob from `ParserDiagnostics` |

**Unique:** `(file_hash)` — prevents re-importing the same file.

### `merchants`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `name` | TEXT | Display name |
| `normalized_name` | TEXT | For matching — **unique** |
| `created_at` / `updated_at` | TEXT | |

### `categories`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `name` | TEXT | |
| `parent_id` | INTEGER NULL | FK to `categories.id` for sub-categories |
| `color` | TEXT NULL | Hex string |
| `icon` | TEXT NULL | SF Symbol name |
| `created_at` / `updated_at` | TEXT | |

Seeded on first run with the default category set — see spec §19 and `Persistence/Seeder.swift`.

### `accounts`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `name` | TEXT | |
| `institution_name` | TEXT NULL | |
| `account_type` | TEXT | `checking` \| `savings` \| `credit_card` \| `wallet` |
| `last_digits` | TEXT NULL | |
| `created_at` / `updated_at` | TEXT | |

### `cards`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `account_id` | INTEGER | FK to `accounts.id` |
| `holder_name` | TEXT NULL | |
| `last_digits` | TEXT | |
| `network` | TEXT NULL | Visa, Mastercard, etc. |
| `created_at` / `updated_at` | TEXT | |

## Schema v2 (Phase 2 — Local Memory)

Adds user-correction memory and rule-based categorization.

### `merchant_aliases`

Map variants ("UBER *TRIP", "UBER TRIP SP") to a canonical merchant.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `merchant_id` | INTEGER | FK |
| `alias` | TEXT | Pattern matched against `description_normalized` |
| `source` | TEXT | `user` \| `system` \| `llm` |
| `created_at` | TEXT | |

### `categorization_rules`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `name` | TEXT | User-friendly label |
| `pattern` | TEXT | The match pattern |
| `pattern_type` | TEXT | `contains` \| `regex` \| `exact` \| `merchant` \| `amount_range` |
| `merchant_id` | INTEGER NULL | |
| `category_id` | INTEGER | FK |
| `priority` | INTEGER | Higher wins within the same pattern type |
| `created_by` | TEXT | `user` \| `system` \| `llm` |
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
| `correction_type` | TEXT | `category` \| `merchant` \| `amount` \| `date` |
| `note` | TEXT NULL | |
| `created_at` | TEXT | |

## Schema v3+ (Later Phases)

- **Phase 4:** A `linked_transaction_id` column on `transactions` to connect a bank-side credit card payment to the corresponding card import batch. Possibly a small `transaction_links` join table instead.
- **Phase 5:** An `llm_suggestions` table caching LLM responses (optional).

Each schema change ships as a versioned migration. Never mutate a shipped migration — always add a new one.
