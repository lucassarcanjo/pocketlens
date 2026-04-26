import SwiftUI
import Charts
import Domain
import Persistence

/// Trailing N-month spending trend bar chart. The window is decoupled from
/// the dashboard's period picker on purpose — the trend's job is to give a
/// baseline against which the selected period can be judged. Honours the
/// active category cross-filter via `DashboardViewModel`.
struct MonthlyTrendChart: View {

    let rows: [AggregateQueries.MonthTotal]
    /// Currently-selected period start. The matching trend bar gets the
    /// accent treatment so users can see which month the rest of the
    /// dashboard is showing.
    let highlightMonthStart: Date?

    private var hasAnyData: Bool {
        rows.contains { $0.total.minorUnits > 0 }
    }

    var body: some View {
        DashboardCard(title: "Spending trend (last \(rows.count) months)") {
            if !hasAnyData {
                EmptyDashboardSection(message: "No spending recorded yet.")
            } else {
                Chart(rows, id: \.monthStart) { row in
                    BarMark(
                        x: .value("Month", row.monthStart, unit: .month),
                        y: .value("Total", row.total.minorUnits)
                    )
                    .foregroundStyle(isHighlighted(row.monthStart) ? Color.accentColor : Color.secondary.opacity(0.6))
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(monthLabel(date))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minor = value.as(Int.self), let currency = rows.first?.total.currency {
                                Text(DashboardFormatters.formatShort(
                                    Money(minorUnits: minor, currency: currency)
                                ))
                                .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    private func isHighlighted(_ monthStart: Date) -> Bool {
        guard let highlight = highlightMonthStart else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.isDate(monthStart, equalTo: highlight, toGranularity: .month)
    }

    private func monthLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}
