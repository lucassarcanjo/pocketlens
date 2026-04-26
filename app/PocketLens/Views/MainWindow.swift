import SwiftUI

enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
    case transactions
    case review
    case imports
    case categories
    case rules
    case dashboard
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .transactions: return "Transactions"
        case .review:       return "Review"
        case .imports:      return "Imports"
        case .categories:   return "Categories"
        case .rules:        return "Rules"
        case .dashboard:    return "Dashboard"
        case .settings:     return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .transactions: return "list.bullet.rectangle"
        case .review:       return "checklist"
        case .imports:      return "tray.and.arrow.down"
        case .categories:   return "tag"
        case .rules:        return "slider.horizontal.3"
        case .dashboard:    return "chart.bar.xaxis"
        case .settings:     return "gearshape"
        }
    }
}

struct MainWindow: View {
    @State private var selection: SidebarSection? = .dashboard

    /// Pre-set when navigating from the dashboard's attention cards.
    @State private var reviewInitialFilter: ReviewView.Filter = .all
    /// Bumped on each cross-screen jump so `ReviewView` re-inits its `@State`
    /// `filter` from the new `initialFilter`.
    @State private var reviewSessionId = UUID()

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { item in
                Label(item.label, systemImage: item.systemImage)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("PocketLens")
        } detail: {
            switch selection ?? .dashboard {
            case .transactions: TransactionsView()
            case .review:
                ReviewView(initialFilter: reviewInitialFilter)
                    .id(reviewSessionId)
            case .imports:      ImportsView()
            case .categories:   CategoriesView()
            case .rules:        RulesListView()
            case .dashboard:
                DashboardView(navigateToReview: { filter in
                    reviewInitialFilter = filter
                    reviewSessionId = UUID()
                    selection = .review
                })
            case .settings:     SettingsView()
            }
        }
    }
}
