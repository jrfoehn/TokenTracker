import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel

    @State private var anthropicKey: String = ""
    @State private var openAIKey: String = ""
    @State private var anthropicSaved = false
    @State private var openAISaved = false

    @State private var awsAccessKeyId: String = ""
    @State private var awsSecretAccessKey: String = ""
    @State private var awsSessionToken: String = ""
    @State private var awsSaved = false

    private let bedrockRegions = [
        "us-east-1", "us-east-2", "us-west-2",
        "eu-central-1", "eu-west-1", "eu-west-3",
        "ap-northeast-1", "ap-southeast-1", "ap-southeast-2",
        "ap-south-1", "ca-central-1", "sa-east-1",
    ]

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
        .frame(width: 520, height: 520)
        .onAppear {
            anthropicKey = KeychainHelper.anthropicKey ?? ""
            openAIKey = KeychainHelper.openAIKey ?? ""
            awsAccessKeyId = KeychainHelper.awsAccessKeyId ?? ""
            awsSecretAccessKey = KeychainHelper.awsSecretAccessKey ?? ""
            awsSessionToken = KeychainHelper.awsSessionToken ?? ""
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

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("AWS Bedrock", systemImage: "cloud.fill")
                        .font(.headline)
                    Text("Requires an IAM user/role with cloudwatch:GetMetricData and cloudwatch:ListMetrics on namespace AWS/Bedrock.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Access Key ID (AKIA… or ASIA…)", text: $awsAccessKeyId)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Secret Access Key", text: $awsSecretAccessKey)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Session Token (optional, for STS creds)", text: $awsSessionToken)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Picker("Region", selection: $viewModel.bedrockRegion) {
                            ForEach(bedrockRegions, id: \.self) { region in
                                Text(region).tag(region)
                            }
                        }
                        .pickerStyle(.menu)

                        Spacer()

                        Button(awsSaved ? "Saved" : "Save") {
                            KeychainHelper.awsAccessKeyId = awsAccessKeyId
                            KeychainHelper.awsSecretAccessKey = awsSecretAccessKey
                            KeychainHelper.awsSessionToken = awsSessionToken
                            awsSaved = true
                            viewModel.refresh()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                awsSaved = false
                            }
                        }
                        .disabled(awsAccessKeyId.isEmpty || awsSecretAccessKey.isEmpty)
                    }

                    if KeychainHelper.awsAccessKeyId != nil, KeychainHelper.awsSecretAccessKey != nil {
                        Label("Credentials stored in Keychain", systemImage: "checkmark.circle.fill")
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
                Toggle("AWS Bedrock", isOn: $viewModel.enabledBedrock)
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
