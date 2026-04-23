import Foundation
import SwiftUI

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var providerUsages: [ProviderUsage] = []
    @Published var isLoading = false
    @Published var errors: [String] = []
    @Published var lastRefresh: Date?
    @Published var dayRange: Int = 7

    @AppStorage("refreshIntervalMinutes") var refreshInterval: Int = 5
    @AppStorage("enabledOpenAI") var enabledOpenAI: Bool = true
    @AppStorage("enabledAnthropic") var enabledAnthropic: Bool = true
    @AppStorage("enabledBedrock") var enabledBedrock: Bool = false
    @AppStorage("bedrockRegion") var bedrockRegion: String = "us-east-1"

    private var refreshTimer: Timer?

    var totalCost: Double {
        providerUsages.reduce(0) { $0 + $1.totalCost }
    }

    var totalTokens: Int {
        providerUsages.reduce(0) { $0 + $1.totalInputTokens + $1.totalOutputTokens }
    }

    var menuBarTitle: String {
        if isLoading && providerUsages.isEmpty { return "..." }
        if providerUsages.isEmpty { return "$-" }
        return "$\(String(format: "%.2f", totalCost))"
    }

    func startAutoRefresh() {
        refresh()
        scheduleTimer()
    }

    func scheduleTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(refreshInterval * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        errors = []

        Task {
            var results: [ProviderUsage] = []
            var newErrors: [String] = []

            if enabledAnthropic, KeychainHelper.anthropicKey != nil {
                do {
                    let usage = try await UsageService.shared.fetchAnthropicUsage(days: dayRange)
                    results.append(usage)
                } catch {
                    newErrors.append(error.localizedDescription)
                }
            }

            if enabledOpenAI, KeychainHelper.openAIKey != nil {
                do {
                    let usage = try await UsageService.shared.fetchOpenAIUsage(days: dayRange)
                    results.append(usage)
                } catch {
                    newErrors.append(error.localizedDescription)
                }
            }

            let bedrockEnabled = enabledBedrock
            let region = bedrockRegion
            if bedrockEnabled,
               KeychainHelper.awsAccessKeyId != nil,
               KeychainHelper.awsSecretAccessKey != nil {
                do {
                    let usage = try await UsageService.shared.fetchBedrockUsage(days: dayRange, region: region)
                    results.append(usage)
                } catch {
                    newErrors.append(error.localizedDescription)
                }
            }

            self.providerUsages = results
            self.errors = newErrors
            self.isLoading = false
            self.lastRefresh = Date()
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }
}
