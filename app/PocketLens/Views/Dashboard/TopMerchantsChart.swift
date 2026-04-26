import SwiftUI
import Charts
import Persistence

/// Horizontal bar chart of the top merchants by spend in the active currency.
struct TopMerchantsChart: View {

    let rows: [AggregateQueries.MerchantTotal]

    var body: some View {
        DashboardCard(title: "Top merchants") {
            if rows.isEmpty {
                EmptyDashboardSection(message: "No merchant activity in this period.")
            } else {
                Chart(rows, id: \.merchantNormalized) { row in
                    BarMark(
                        x: .value("Total", row.total.minorUnits),
                        y: .value("Merchant", row.merchantNormalized)
                    )
                    .foregroundStyle(.tint)
                    .annotation(position: .trailing) {
                        Text(DashboardFormatters.format(row.total))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(minHeight: CGFloat(rows.count * 28 + 24))
            }
        }
    }
}
