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
    @State private var selection: SidebarSection? = .transactions

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { item in
                Label(item.label, systemImage: item.systemImage)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("PocketLens")
        } detail: {
            switch selection ?? .transactions {
            case .transactions: TransactionsView()
            case .review:       ReviewView()
            case .imports:      ImportsView()
            case .categories:   CategoriesView()
            case .rules:        RulesListView()
            case .dashboard:    DashboardPlaceholderView()
            case .settings:     SettingsView()
            }
        }
    }
}

struct DashboardPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Dashboard")
                .font(.title2.weight(.semibold))
            Text("Charts and rollups land in v0.3.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
