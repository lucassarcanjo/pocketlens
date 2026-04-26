import SwiftUI
import Persistence

/// Top-N largest single-row purchases in the active currency.
struct LargestTransactionsList: View {

    let rows: [AggregateQueries.LargestTransaction]

    var body: some View {
        DashboardCard(title: "Largest transactions") {
            if rows.isEmpty {
                EmptyDashboardSection(message: "No purchases in this period.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.transactionId) { idx, row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.merchantNormalized)
                                    .font(.callout)
                                HStack(spacing: 6) {
                                    Text(DashboardFormatters.date.string(from: row.postedDate))
                                    Text("•")
                                    Text("•••• \(row.cardLast4)")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(DashboardFormatters.format(row.amount))
                                .font(.callout.monospacedDigit())
                        }
                        .padding(.vertical, 8)
                        if idx != rows.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}
