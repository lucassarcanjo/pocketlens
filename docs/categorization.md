# Categorization

PocketLens assigns a category to every imported transaction and attaches two things alongside the category:

1. A **confidence score** in `[0, 1]`.
2. A human-readable **reason string** explaining why the category was chosen.

Both surface in the UI. A category without a visible reason is a bug.

## Priority Order

The `CategorizationEngine` evaluates strategies in this fixed order. The first hit wins. Later strategies aren't tried.

1. **Exact user correction** — this exact transaction (or matching fingerprint) was previously re-categorized by the user.
2. **Merchant alias match** — normalized description collapses to a known merchant that has a preferred category.
3. **User-created rule** — highest-priority enabled rule whose pattern matches.
4. **Bank-category mapping** — the issuer's own category label (`bank_category_raw` on the transaction, e.g. Itaú's `ALIMENTAÇÃO`/`VEÍCULOS`/`TURISMO E ENTRETENIM.`) maps to a PocketLens category via a seeded table. High-quality prior because the issuer already classified the merchant.
5. **Keyword rule** — system-seeded rules (e.g., `contains "UBER"` → Transportation).
6. **Similar transaction match** — cosine/Jaccard similarity above threshold against a previously-categorized transaction.
7. **LLM suggestion** — available only if a provider is configured (Phase 5). Stored as a suggestion, not applied automatically unless confidence is above a user-configurable threshold.
8. **Uncategorized / needs review** — nothing matched.

## Confidence Tiers

Per spec §11.2:

| Score | Meaning | UI behavior |
|---|---|---|
| 0.95 – 1.00 | Very high — probably doesn't need review | Applied silently |
| 0.80 – 0.94 | Good — can be auto-applied | Applied, badged |
| 0.50 – 0.79 | Medium — should be reviewed | Applied, flagged for review |
| < 0.50 | Low — needs manual review | Left uncategorized with LLM suggestion visible |

Each strategy emits confidence within a well-defined band:

| Strategy | Emits |
|---|---|
| Exact user correction | 1.00 |
| Merchant alias | 0.95 |
| User-created rule | 0.90 |
| Bank-category mapping | 0.85 |
| Keyword rule | 0.80 |
| Similarity | 0.50 – 0.85 (scales with similarity score) |
| LLM suggestion | Whatever the provider returns (capped at 0.80 unless user-configured higher) |
| No match | 0.00 |

## Reason Strings

Every transaction's `categorization_reason` column stores a short English phrase. Examples:

| Transaction | Category | Reason |
|---|---|---|
| `APPLECOMBILL` | Subscriptions | Matched merchant alias: Apple |
| `HORTIPLUS MIGUEL` | Groceries | User rule: "Groceries at HORTIPLUS" |
| `UBER *TRIP 123` | Transportation | Keyword rule: contains "UBER" |
| `SAUIPE RESORTS` | Travel | LLM suggestion (high confidence) |
| `MP *ELIZAHLTDA` | Uncategorized | No strong rule found |

The `CategorizationReason` enum in `Domain` encodes each strategy so UI can style them consistently.

## Adding a Rule

Users can create a rule from any transaction via the UI (spec §16.3). The flow:

1. Select a transaction.
2. Choose "Create rule from this transaction".
3. The rule editor opens pre-filled with:
   - Pattern type suggestion (usually `contains` on the normalized description or `merchant`).
   - The current category.
4. User edits and saves.

Rules support these pattern types:

- `contains` — substring match on normalized description.
- `regex` — full regex match.
- `exact` — exact match on normalized description.
- `merchant` — `merchant_id` equality.
- `amount_range` — numeric range on amount.

## Memory Lifecycle

Every user correction writes to `user_corrections`. The engine reads this table first at categorization time. There is **no training step** — memory is always consulted live.

Similarly, merchant aliases created during correction flows are written to `merchant_aliases` and are available immediately to future imports.

## Tuning the Similarity Strategy

The initial similarity threshold is **0.85** on normalized-description cosine distance. This is a conservative starting point — we'd rather mark something "uncategorized" than apply a wrong category automatically. Tune with real data in Phase 2.

## Related Docs

- [`data-model.md`](data-model.md) — schema for rules, corrections, aliases.
- [`llm-integration.md`](llm-integration.md) — how the LLM fits into priority slot 6.
