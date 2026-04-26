import SwiftUI

/// Segmented preset picker plus a pair of date pickers when `custom` is
/// selected. Bound directly to `DashboardViewModel` so changes propagate
/// straight to `@AppStorage`.
struct DateRangePicker: View {

    @ObservedObject var viewModel: DashboardViewModel
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Period", selection: $viewModel.preset) {
                ForEach(DashboardDateRangePreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 520)
            .onChange(of: viewModel.preset) { _, _ in onChange() }

            if viewModel.preset == .custom {
                HStack(spacing: 12) {
                    DatePicker(
                        "From",
                        selection: $viewModel.customStart,
                        displayedComponents: .date
                    )
                    .onChange(of: viewModel.customStart) { _, _ in onChange() }
                    DatePicker(
                        "To",
                        selection: $viewModel.customEnd,
                        displayedComponents: .date
                    )
                    .onChange(of: viewModel.customEnd) { _, _ in onChange() }
                }
                .frame(maxWidth: 520)
            }
        }
    }
}
