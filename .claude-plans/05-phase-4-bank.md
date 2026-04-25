# Phase 4 — Bank Statement Import (v0.4)

## Goal
Extend PocketLens beyond credit cards. Import bank account statements from CSV, OFX, and PDF; unify them into the same transaction model; link credit card payments on the bank side to the corresponding credit card bills.

## Definition of Done
- [ ] CSV bank statements parse via a configurable column-mapping UI (date col, description col, amount col, etc.).
- [ ] OFX bank statements parse automatically (structured format).
- [ ] At least one bank's PDF statement parses (TBD which — depends on user's bank).
- [ ] Transactions from bank statements have `source_type = bankStatement` and an `account_id`.
- [ ] Classifier tags each bank transaction as `debit | credit | payment | transfer | fee | refund`.
- [ ] Credit card payment entries on the bank side are matched to the corresponding `ImportBatch` on the card side (amount + date proximity).
- [ ] Cash flow view shows money in vs. money out per month.

## Tasks

### Domain
- [ ] `Account.accountType` enum finalized: `checking | savings | creditCard | wallet`.
- [ ] `TransactionLink` entity (or a `linkedTransactionId` column) so a bank-side payment transaction points to the matching card-side import.

### Persistence
- [ ] Schema v3 migration — new column or join table for cross-source transaction links.
- [ ] Queries for cash flow aggregates.

### Importing
- [ ] `CSVImporter` — header detection + column-mapping config stored per account.
- [ ] `OFXImporter` — parse `<STMTTRN>` blocks, handle FITID (natural transaction id).
- [ ] `BankStatementParser` protocol + first concrete impl for one real bank.
- [ ] `BankTransactionClassifier` — keyword + amount-sign heuristics for transaction type.
- [ ] `CreditCardPaymentMatcher` — given a bank `payment` transaction, find the closest card `ImportBatch` by amount/date.

### App target
- [ ] Accounts screen — add/edit/delete accounts, set account type.
- [ ] CSV import wizard — preview first N rows, let user map columns, save mapping.
- [ ] Cash flow chart on dashboard.

## Dependencies
- Requires Phase 3 ✅ (dashboard framework in place; cash flow plugs into it).

## Test Coverage
- CSV parser — various delimiters, quoted fields, decimal/thousand-separator variants (PT-BR uses comma as decimal).
- OFX parser — real-world malformed OFX samples (banks produce creative violations of the spec).
- Classifier — labeled test set per transaction type.
- Payment matcher — happy path, ambiguous match, no match.

## Open Questions
- Which bank's PDF statement to target first?
- FITID: use as primary dedup key when present, fall back to fingerprint otherwise.

## Next Action
Ask the user which bank(s) they want supported first. Start with OFX (structured, lower variability) before CSV.
