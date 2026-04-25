# Phase 2 — Local Memory (v0.2)

## Goal
Categorization learns from user corrections. When a user re-imports a similar statement, previously-corrected transactions get the right category automatically — with a visible reason.

## Definition of Done
- [ ] Every categorized transaction has a non-empty `categorization_reason` string.
- [ ] Every categorized transaction has a `confidence` score in [0, 1].
- [ ] User corrections are stored in `user_corrections` and applied to future imports automatically.
- [ ] Merchant aliases collapse variants ("UBER *TRIP", "UBER TRIP SP", "Uber BR") to a single merchant.
- [ ] Rules support all pattern types from §12.6: `contains`, `regex`, `exact`, `merchant`, `amount_range`.
- [ ] Transaction review UI surfaces low-confidence items (spec §16.3).
- [ ] User can create a rule from a selected transaction (spec §16.3).

## Tasks

### Domain additions
- [ ] `MerchantAlias` entity (§12.4).
- [ ] `CategorizationRule` entity (§12.6) with `PatternType` enum.
- [ ] `UserCorrection` entity (§12.7).
- [ ] `CategorizationSuggestion` value type: `categoryId`, `confidence`, `reason`.
- [ ] `CategorizationReason` enum representing the §11.1 priority order.

### Persistence additions
- [ ] Schema v2 migration — add `merchant_aliases`, `categorization_rules`, `user_corrections`.
- [ ] Repositories for new entities.
- [ ] `CategorizationMemory` — query interface keyed by normalized description / merchant / fingerprint.

### Categorization package
- [ ] `CategorizationEngine` — evaluates in priority order (§11.1):
  1. Exact user correction match
  2. Merchant alias → merchant → rule
  3. User-created rule
  4. Keyword (system) rule
  5. Similarity to prior categorized transaction
  6. LLM suggestion (stub — real impl Phase 5)
  7. `Uncategorized`
- [ ] `RuleBasedCategorizer` — contains/regex/exact/merchant/amount_range.
- [ ] `MerchantAliasMatcher`.
- [ ] `SimilarityCategorizer` — cosine / Jaccard on normalized descriptions; threshold-tuned.
- [ ] Confidence scoring aligned with spec §11.2 tiers (>=0.95, 0.80–0.94, 0.50–0.79, <0.50).
- [ ] Each result carries a `reason` string suitable for UI display (spec §11.3).

### App target UI
- [ ] Review screen — filter by uncategorized, low-confidence, needs-review.
- [ ] Bulk category assignment.
- [ ] "Create rule from this transaction" action — opens pre-filled rule editor.
- [ ] "Add merchant alias" action — opens pre-filled alias editor.
- [ ] Rule list + CRUD UI.
- [ ] Every transaction row shows a small badge with the categorization reason.

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
- **Confidence tier tests** — assert each strategy emits score in its documented band.

## Open Questions
- Similarity threshold — start at 0.85 cosine, tune against real data.
- Regex safety — should we sandbox user regex patterns against ReDoS? (Low priority; single-user local app.)

## Next Action
Add schema v2 migration (`merchant_aliases`, `categorization_rules`, `user_corrections`). Then build `CategorizationEngine` with the priority chain, starting with exact user-correction lookup.
