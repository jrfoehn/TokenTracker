import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider().padding(.vertical, 4)

            if viewModel.providerUsages.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                usageList
            }

            if !viewModel.errors.isEmpty {
                errorSection
            }

            Divider().padding(.vertical, 4)
            footerSection
        }
        .padding(12)
        .frame(width: 340)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Token Tracker")
                    .font(.headline)
                Text("Last \(viewModel.dayRange) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("$\(String(format: "%.2f", viewModel.totalCost))")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(costColor(viewModel.totalCost))
                Text(formatTokens(viewModel.totalTokens) + " tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No API keys configured")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Add your admin API keys in Settings")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Usage List

    private var usageList: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.providerUsages) { usage in
                providerCard(usage)
            }
        }
    }

    private func providerCard(_ usage: ProviderUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                providerIcon(usage.provider)
                Text(usage.provider.rawValue)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("$\(String(format: "%.2f", usage.totalCost))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(costColor(usage.totalCost))
            }

            HStack(spacing: 12) {
                tokenBadge(label: "In", count: usage.totalInputTokens, color: .blue)
                tokenBadge(label: "Out", count: usage.totalOutputTokens, color: .green)
                if usage.totalCachedTokens > 0 {
                    tokenBadge(label: "Cache", count: usage.totalCachedTokens, color: .orange)
                }
            }

            if !usage.models.isEmpty {
                modelBreakdown(usage.models)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func providerIcon(_ provider: Provider) -> some View {
        Image(systemName: provider == .anthropic ? "brain.head.profile" : "sparkles")
            .font(.caption)
            .foregroundStyle(provider == .anthropic ? .orange : .green)
    }

    private func tokenBadge(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(label): \(formatTokens(count))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func modelBreakdown(_ models: [ModelUsage]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(models.prefix(5)) { model in
                HStack {
                    Text(model.model)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(formatTokens(model.inputTokens + model.outputTokens) + " tok")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("$\(String(format: "%.2f", model.cost))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
            if models.count > 5 {
                Text("+\(models.count - 5) more models")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Errors

    private var errorSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(viewModel.errors, id: \.self) { error in
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            if let lastRefresh = viewModel.lastRefresh {
                Text("Updated \(lastRefresh, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()

            Button(action: { viewModel.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)

            Picker("", selection: $viewModel.dayRange) {
                Text("1d").tag(1)
                Text("7d").tag(7)
                Text("30d").tag(30)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .onChange(of: viewModel.dayRange) {
                viewModel.refresh()
            }

            Button(action: { openSettings() }) {
                Image(systemName: "gearshape")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Image(systemName: "power")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func costColor(_ cost: Double) -> Color {
        if cost > 50 { return .red }
        if cost > 10 { return .orange }
        return .primary
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
