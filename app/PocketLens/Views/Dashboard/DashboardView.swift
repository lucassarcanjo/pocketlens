import SwiftUI
import Domain
import Persistence

/// Two-column responsive dashboard. Aggregates load via `DashboardViewModel`;
/// user actions on the date range picker re-issue queries against the
/// already-open SQLite store.
struct DashboardView: View {

    @EnvironmentObject private var app: AppState
    @StateObject private var vm = DashboardViewModel()

    /// Parent (MainWindow) injects this so the attention cards can switch
    /// the sidebar selection to Review with the right filter.
    var navigateToReview: (ReviewView.Filter) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                NeedsAttentionCards(
                    uncategorizedCount: vm.uncategorizedCount,
                    needsReviewCount: vm.needsReviewCount,
                    onTapUncategorized: { navigateToReview(.uncategorized) },
                    onTapNeedsReview:   { navigateToReview(.needsReview) }
                )
                if vm.selectedCategoryId != nil {
                    filterPill
                }
                MonthlyTrendChart(
                    rows: vm.monthlyTrend,
                    highlightMonthStart: vm.interval().start
                )
                totalsCard
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 20) {
                            categoryChart
                            LargestTransactionsList(rows: vm.largestTransactions)
                        }
                        VStack(spacing: 20) {
                            TopMerchantsChart(rows: vm.topMerchants)
                            CreditCardTotalsCard(rows: vm.totalsByCard)
                        }
                    }
                    VStack(spacing: 20) {
                        categoryChart
                        TopMerchantsChart(rows: vm.topMerchants)
                        LargestTransactionsList(rows: vm.largestTransactions)
                        CreditCardTotalsCard(rows: vm.totalsByCard)
                    }
                }
                if let err = vm.loadError {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .padding(20)
        }
        .navigationTitle("Dashboard")
        .task { await vm.reload(store: app.store) }
        .onChange(of: app.store?.queue.path) { _, _ in
            Task { await vm.reload(store: app.store) }
        }
    }

    private var categoryChart: some View {
        SpendingByCategoryChart(
            rows: vm.spendingByCategory,
            selectedCategoryId: vm.selectedCategoryId,
            onSelect: { id, name in
                Task { await vm.setCategoryFilter(id, name: name, store: app.store) }
            }
        )
    }

    private var filterPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(.tint)
            Text("Filtering by ")
                .foregroundStyle(.secondary)
            + Text(vm.selectedCategoryName ?? "category")
                .fontWeight(.semibold)
            Spacer()
            Button {
                Task { await vm.setCategoryFilter(nil, name: nil, store: app.store) }
            } label: {
                Label("Clear", systemImage: "xmark.circle.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            DateRangePicker(viewModel: vm) {
                Task { await vm.reload(store: app.store) }
            }
            if vm.totalsByCurrency.count > 1 {
                Picker("Currency", selection: $vm.selectedCurrency) {
                    ForEach(vm.totalsByCurrency, id: \.currency) { t in
                        Text(t.currency.rawValue).tag(t.currency)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .onChange(of: vm.selectedCurrency) { _, _ in
                    Task { await vm.reload(store: app.store) }
                }
            }
        }
    }

    private var totalsCard: some View {
        DashboardCard(title: "Total spending") {
            if vm.totalsByCurrency.isEmpty {
                EmptyDashboardSection(message: "Nothing yet for this period.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(vm.totalsByCurrency, id: \.currency) { row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.currency.rawValue)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .leading)
                            Text(DashboardFormatters.format(row.total))
                                .font(.title2.weight(.semibold).monospacedDigit())
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Shared sub-components

/// Bordered titled container reused by every dashboard tile.
struct DashboardCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.15))
        )
    }
}

struct EmptyDashboardSection: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}
