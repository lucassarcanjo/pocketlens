import SwiftUI

enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
    case transactions
    case imports
    case categories
    case dashboard
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .transactions: return "Transactions"
        case .imports:      return "Imports"
        case .categories:   return "Categories"
        case .dashboard:    return "Dashboard"
        case .settings:     return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .transactions: return "list.bullet.rectangle"
        case .imports:      return "tray.and.arrow.down"
        case .categories:   return "tag"
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
            case .imports:      ImportsView()
            case .categories:   CategoriesView()
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
