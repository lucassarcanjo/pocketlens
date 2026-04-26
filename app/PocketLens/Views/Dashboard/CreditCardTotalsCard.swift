import SwiftUI
import Persistence

/// Per-card spending in the active currency. Person-level grouping is
/// deferred — see Phase 3 plan's Open Questions.
struct CreditCardTotalsCard: View {

    let rows: [AggregateQueries.CardTotal]

    var body: some View {
        DashboardCard(title: "Credit cards") {
            if rows.isEmpty {
                EmptyDashboardSection(message: "No card activity in this period.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.cardId) { idx, row in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.cardNickname ?? row.cardHolderName)
                                    .font(.callout)
                                Text("•••• \(row.cardLast4)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(DashboardFormatters.format(row.total))
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
