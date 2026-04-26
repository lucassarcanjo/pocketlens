import SwiftUI
import Charts
import Persistence

/// Pie chart of category share + ranked bar list. Side-by-side on wide
/// detail panes, stacked on narrow ones. Tapping a category toggles the
/// dashboard's cross-filter via `onSelect`; the active selection is
/// highlighted while non-selected categories dim.
struct SpendingByCategoryChart: View {

    let rows: [AggregateQueries.CategoryTotal]
    let selectedCategoryId: Int64?
    /// Tap handler — receives the row's `(categoryId, categoryName)`. Passing
    /// the same id again is the toggle-off signal; the view model handles
    /// that. `categoryId == nil` rows (uncategorized bucket) are not
    /// selectable because every other query treats them as "no filter."
    var onSelect: (Int64, String?) -> Void

    private var rowsToShow: [AggregateQueries.CategoryTotal] {
        rows.filter { $0.total.minorUnits > 0 }
    }

    private func opacity(for row: AggregateQueries.CategoryTotal) -> Double {
        guard let selected = selectedCategoryId else { return 1.0 }
        return row.categoryId == selected ? 1.0 : 0.35
    }

    var body: some View {
        DashboardCard(title: "Spending by category") {
            if rowsToShow.isEmpty {
                EmptyDashboardSection(message: "No spending in this period.")
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        pie.frame(width: 220, height: 220)
                        bars
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        pie.frame(height: 220)
                        bars
                    }
                }
            }
        }
    }

    private var pie: some View {
        Chart(rowsToShow, id: \.categoryId) { row in
            SectorMark(
                angle: .value("Total", row.total.minorUnits),
                innerRadius: .ratio(0.55),
                angularInset: 1
            )
            .foregroundStyle(DashboardFormatters.color(hex: row.categoryColor))
            .opacity(opacity(for: row))
        }
    }

    private var bars: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rowsToShow, id: \.categoryId) { row in
                Button {
                    if let id = row.categoryId {
                        onSelect(id, row.categoryName)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(DashboardFormatters.color(hex: row.categoryColor))
                            .frame(width: 10, height: 10)
                        Text(row.categoryName ?? "Uncategorized")
                            .font(.callout)
                            .foregroundStyle(row.categoryName == nil ? .secondary : .primary)
                        Spacer(minLength: 12)
                        Text(DashboardFormatters.format(row.total))
                            .font(.callout.monospacedDigit())
                    }
                    .contentShape(Rectangle())
                    .opacity(opacity(for: row))
                }
                .buttonStyle(.plain)
                .disabled(row.categoryId == nil)
            }
        }
    }
}
