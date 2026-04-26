# Phase 2 — Local Memory (v0.2)

## Goal
Categorization learns from user corrections. When a user re-imports a similar statement, previously-corrected transactions get the right category automatically — with a visible reason.

## Definition of Done
- [x] Every categorized transaction has a non-empty `categorization_reason` string.
- [x] Every categorized transaction has a `confidence` score in [0, 1].
- [x] User corrections are stored in `user_corrections` and applied to future imports automatically.
- [x] Merchant aliases collapse variants ("UBER *TRIP", "UBER TRIP SP", "Uber BR") to a single merchant.
- [x] Rules support all pattern types from §12.6: `contains`, `regex`, `exact`, `merchant`, `amount_range`.
- [x] Transaction review UI surfaces low-confidence items (spec §16.3).
- [x] User can create a rule from a selected transaction (spec §16.3).

## Tasks

### Domain additions
- [x] `MerchantAlias` entity (§12.4).
- [x] `CategorizationRule` entity (§12.6) with `PatternType` enum.
- [x] `UserCorrection` entity (§12.7).
- [x] `CategorizationSuggestion` value type: `categoryId`, `confidence`, `reason`.
- [x] `CategorizationReason` enum representing the §11.1 priority order.

### Persistence additions
- [x] Schema v2 migration — add `merchant_aliases`, `categorization_rules`, `user_corrections`, `bank_category_mappings`.
- [x] Repositories for new entities.
- [x] `CategorizationMemory` — folded into the per-strategy repo queries (`UserCorrectionRepository`, `MerchantAliasRepository`, `CategorizationRuleRepository`, `BankCategoryMappingRepository`, `TransactionRepository.categorized()` / `findByFingerprint(_:)`). No standalone facade — strategies own their lookups.
- [x] Seed `bank_category_mappings` for Itaú on first run (extend `DefaultDataSeeder`). Idempotent — re-running must not duplicate rows.

### Categorization package
- [x] `CategorizationEngine` — evaluates in priority order (matches `docs/categorization.md`):
  1. Exact user correction match
  2. Merchant alias → merchant → rule
  3. User-created rule
  4. Bank-category mapping (`bank_category_raw` → PocketLens category via seeded table)
  5. Keyword (system) rule
  6. Similarity to prior categorized transaction
  7. LLM suggestion (stub — real impl Phase 5)
  8. `Uncategorized`
- [x] `RuleStrategy` — contains/regex/exact/merchant/amount_range.
- [x] `MerchantAliasStrategy`.
- [x] `BankCategoryStrategy` — looks up `(bank_name, bank_category_raw)` against `bank_category_mappings`; falls back to wildcard row (`bank_name = NULL`) when no issuer-specific mapping exists. Confidence band 0.85.
- [x] `SimilarityStrategy` — Jaccard on character bigrams of `merchant_normalized`; default threshold 0.85, scaled into 0.50–0.85 confidence band.
- [x] Confidence scoring aligned with spec §11.2 tiers (>=0.95, 0.80–0.94, 0.50–0.79, <0.50).
- [x] Each result carries a `reason` string suitable for UI display (spec §11.3).

### App target UI
- [x] Review screen — filter by uncategorized, low-confidence, needs-review.
- [ ] Bulk category assignment. (deferred — single-row picker covers Phase-2 DoD; revisit in Phase 3 if review queue gets long.)
- [x] "Create rule from this transaction" action — opens pre-filled rule editor.
- [x] "Add merchant alias" action — opens pre-filled alias editor.
- [x] Rule list + CRUD UI.
- [x] Every transaction row shows a small badge with the categorization reason.

## Files Touched (anticipated)
- `packages/Domain/Sources/Domain/` — new entities.
- `packages/Persistence/Sources/Persistence/` — schema v2 migration + new repos.
- `packages/Categorization/Sources/Categorization/` — the engine + strategies.
- `app/PocketLens/Views/{ReviewView,RuleEditorView,MerchantAliasEditorView,RulesListView}.swift`.

## Dependencies
- Requires Phase 1 ✅ (needs real transactions to categorize).

## Test Coverage
- **Engine priority tests** — construct scenarios where multiple strategies could match; assert the higher-priority one wins.
- **Rule pattern tests** — each `PatternType` has matching + non-matching cases.
- **Alias collapse tests** — "UBER *TRIP" + "UBER TRIP SP" → same merchant.
- **Correction memory tests** — correct once, re-import, auto-categorized correctly.
- **Bank-category mapping tests** — Itaú `ALIMENTAÇÃO` → Groceries; case-insensitive match; issuer-specific row beats wildcard; missing mapping falls through to next strategy.
- **Confidence tier tests** — assert each strategy emits score in its documented band.

## Open Questions
- Similarity threshold — start at 0.85 cosine, tune against real data.
- Regex safety — should we sandbox user regex patterns against ReDoS? (Low priority; single-user local app.)

## Next Action

**Phase 2 closed 2026-04-25.** Implementation complete (all DoD ticked, 117 SPM tests + 1 app test green, app builds cleanly) and manual smoke test against `fixtures/statements/itau-personnalite-2026-03-private.pdf` passed end-to-end on the user's machine. Move to Phase 3 — see `.claude-plans/04-phase-3-dashboard.md`.

### Phase 2 Backlog (deferred, not blocking Phase 3)

- **Bulk category assignment** in the review queue. Single-row picker covers DoD; deferred until the queue gets long enough that bulk is worth the UX cost.
- **`categorization_reason_key` column** alongside the existing free-text reason. The badge currently infers the structured `CategorizationReason` from the explanation prefix (heuristic in `CategorizationReasonBadge.reason(forExplanation:)`). Cheap to add when we want the structured value at query time.
- **Cross-statement learning** for user corrections. Slot 1 currently keys on fingerprint, which only fires on overlapping re-imports. Phase 4's bank-statement linkage is a natural place to introduce a softer match (`merchant_normalized` alone) so a correction on January's "PADARIA REAL" propagates to February's recurring charge.
- **User-rule seeding** — the system rules table is empty by default. We can seed obvious ones (UBER → Transporte, NETFLIX → Lazer, etc.) when the user's empty-rules state shows up.
