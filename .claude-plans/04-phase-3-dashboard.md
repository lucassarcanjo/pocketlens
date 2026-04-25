# Phase 3 — Dashboard (v0.3)

## Goal
A simple, responsive dashboard that answers "where did my money go this month?" — using Swift Charts over the locally stored data.

## Definition of Done (per spec §14.1)
- [ ] Total spending for selected period.
- [ ] Spending-by-category breakdown (pie + ranked bar).
- [ ] Top merchants (bar chart, ranked).
- [ ] Largest transactions (list, top N).
- [ ] Uncategorized count with click-through to review screen.
- [ ] Transactions-needing-review count with click-through.
- [ ] Credit card total by card / person when data available.
- [ ] Date range selector (This month / Last month / Last 3 months / Custom).

## Tasks
- [ ] Dashboard view model — aggregates via SQL `GROUP BY` in Persistence (not in-memory in Swift).
- [ ] Dashboard view — two-column responsive layout.
- [ ] `SpendingByCategoryChart`.
- [ ] `TopMerchantsChart`.
- [ ] `LargestTransactionsList`.
- [ ] `NeedsAttentionCards` (uncategorized, low-confidence).
- [ ] `CreditCardTotalsCard`.
- [ ] `DateRangePicker`.
- [ ] Persist last-used date range in `UserDefaults`.

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
Write the aggregate SQL queries first — they define the shape of everything the view model consumes.
