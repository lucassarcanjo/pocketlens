# Phase 3 — Dashboard (v0.3)

## Goal
A simple, responsive dashboard that answers "where did my money go this month?" — using Swift Charts over the locally stored data.

## Definition of Done (per spec §14.1)
- [x] Total spending for selected period.
- [x] Spending-by-category breakdown (pie + ranked bar).
- [x] Top merchants (bar chart, ranked).
- [x] Largest transactions (list, top N).
- [x] Uncategorized count with click-through to review screen.
- [x] Transactions-needing-review count with click-through.
- [x] Credit card total by card (Person grouping deferred — see Open Questions).
- [x] Date range selector (This month / Last month / Last 3 months / Custom).

## Tasks
- [x] Dashboard view model — aggregates via SQL `GROUP BY` in Persistence (not in-memory in Swift).
- [x] Dashboard view — two-column responsive layout.
- [x] `SpendingByCategoryChart`.
- [x] `TopMerchantsChart`.
- [x] `LargestTransactionsList`.
- [x] `NeedsAttentionCards` (uncategorized, needs-review).
- [x] `CreditCardTotalsCard`.
- [x] `DateRangePicker`.
- [x] Persist last-used date range in `UserDefaults`.

## Files Touched (anticipated)
- `packages/Persistence/Sources/Persistence/AggregateQueries.swift` — all the SQL for dashboard.
- `app/PocketLens/Views/Dashboard/` — new folder with the view + sub-views.
- `app/PocketLens/ViewModels/DashboardViewModel.swift`.

## Dependencies
- Requires Phase 2 ✅ (meaningful categories attached to transactions).

## Test Coverage
- **Aggregate query tests** — seed known data, assert `spendingByCategory` returns expected totals.
- **Date range edge cases** — month boundaries, timezone handling, empty periods.
- **Snapshot tests** — consider for chart views if we use swift-snapshot-testing.

## Open Questions
- Currency handling in aggregates — if we have mixed BRL/USD transactions, show two totals? (Probably yes; group by currency in SQL.)
- "Person" field is in §12.1 but semantics undefined — who sets it? Likely a card-level or rule-based assignment, deferred.

## Next Action
Phase 3 is closed out (✅ in `00-OVERVIEW.md`). Phase 4 (Bank Statement Import, v0.4) is now ⏭ ready — see `.claude-plans/05-phase-4-bank.md` for its pinned next action.

## Phase 3 Backlog
- **Person-level grouping on `CreditCardTotalsCard`.** Plan defers this — semantics undefined (per-holder? per-rule?). Revisit when card-holder UX surfaces.
- **Currency switcher behavior.** Today the segmented picker only shows when ≥2 currencies appear in the period. Acceptable for v0.3; revisit if multi-currency users want a sticky preference per-period.
- **Snapshot tests for charts.** Plan called these out as optional ("if we use swift-snapshot-testing"). Skipped — Swift Charts output is hard to snapshot reliably and the underlying data is already covered by `AggregateQueriesTests`.
