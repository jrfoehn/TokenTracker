import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel

    @State private var anthropicKey: String = ""
    @State private var openAIKey: String = ""
    @State private var anthropicSaved = false
    @State private var openAISaved = false

    var body: some View {
        TabView {
            apiKeysTab
                .tabItem {
                    Label("API Keys", systemImage: "key.fill")
                }

            preferencesTab
                .tabItem {
                    Label("Preferences", systemImage: "gearshape")
                }
        }
        .frame(width: 480, height: 320)
        .onAppear {
            anthropicKey = KeychainHelper.anthropicKey ?? ""
            openAIKey = KeychainHelper.openAIKey ?? ""
        }
    }

    // MARK: - API Keys Tab

    private var apiKeysTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Anthropic Admin Key", systemImage: "brain.head.profile")
                        .font(.headline)
                    Text("Requires an Admin API key (sk-ant-admin...) from Console > Settings > Admin Keys")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        SecureField("sk-ant-admin-...", text: $anthropicKey)
                            .textFieldStyle(.roundedBorder)
                        Button(anthropicSaved ? "Saved" : "Save") {
                            KeychainHelper.anthropicKey = anthropicKey
                            anthropicSaved = true
                            viewModel.refresh()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                anthropicSaved = false
                            }
                        }
                        .disabled(anthropicKey.isEmpty)
                    }
                    if !anthropicKey.isEmpty && KeychainHelper.anthropicKey != nil {
                        Label("Key stored in Keychain", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("OpenAI Admin Key", systemImage: "sparkles")
                        .font(.headline)
                    Text("Requires an Admin key from platform.openai.com > Settings > Admin Keys")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        SecureField("sk-admin-...", text: $openAIKey)
                            .textFieldStyle(.roundedBorder)
                        Button(openAISaved ? "Saved" : "Save") {
                            KeychainHelper.openAIKey = openAIKey
                            openAISaved = true
                            viewModel.refresh()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                openAISaved = false
                            }
                        }
                        .disabled(openAIKey.isEmpty)
                    }
                    if !openAIKey.isEmpty && KeychainHelper.openAIKey != nil {
                        Label("Key stored in Keychain", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Preferences Tab

    private var preferencesTab: some View {
        Form {
            Section("Providers") {
                Toggle("OpenAI", isOn: $viewModel.enabledOpenAI)
                Toggle("Anthropic", isOn: $viewModel.enabledAnthropic)
            }

            Section("Refresh Interval") {
                Picker("Auto-refresh every", selection: $viewModel.refreshInterval) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                }
                .onChange(of: viewModel.refreshInterval) {
                    viewModel.scheduleTimer()
                }
            }

            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Built with", value: "SwiftUI")
                Text("Token Tracker monitors your LLM API usage and costs from the menu bar. API keys are stored securely in macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
