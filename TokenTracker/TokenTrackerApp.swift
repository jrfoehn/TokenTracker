import SwiftUI

@main
struct TokenTrackerApp: App {
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
                .onAppear {
                    viewModel.startAutoRefresh()
                }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                Text(viewModel.menuBarTitle)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
