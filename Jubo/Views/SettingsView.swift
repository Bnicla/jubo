import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Model Section
                Section("Model") {
                    HStack {
                        Label("Model", systemImage: "brain")
                        Spacer()
                        Text(viewModel.modelInfo)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Status", systemImage: "circle.fill")
                            .foregroundColor(statusColor)
                        Spacer()
                        Text(statusText)
                            .foregroundColor(.secondary)
                    }

                    if viewModel.tokensPerSecond > 0 {
                        HStack {
                            Label("Speed", systemImage: "speedometer")
                            Spacer()
                            Text(String(format: "%.1f tokens/sec", viewModel.tokensPerSecond))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Chat Section
                Section("Chat") {
                    HStack {
                        Label("Messages", systemImage: "bubble.left.and.bubble.right")
                        Spacer()
                        Text("\(viewModel.messages.count)")
                            .foregroundColor(.secondary)
                    }

                    Button(role: .destructive) {
                        viewModel.clearChat()
                        dismiss()
                    } label: {
                        Label("Clear Chat History", systemImage: "trash")
                    }
                }

                // Memory & Learning Section
                Section {
                    HStack {
                        Label("Learned Facts", systemImage: "brain.head.profile")
                        Spacer()
                        Text("\(UserMemory.shared.facts.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Interactions", systemImage: "arrow.left.arrow.right")
                        Spacer()
                        Text("\(UserMemory.shared.patterns.totalInteractions)")
                            .foregroundColor(.secondary)
                    }

                    NavigationLink {
                        LearnedMemoriesView()
                    } label: {
                        Label("View Learned Memories", systemImage: "list.bullet.rectangle")
                    }

                    Button(role: .destructive) {
                        UserMemory.shared.resetAll()
                    } label: {
                        Label("Clear All Learned Data", systemImage: "trash")
                    }
                } header: {
                    Text("Memory & Learning")
                } footer: {
                    Text("Jubo learns your preferences from conversations. All data stays on your device.")
                }

                // About Section
                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0 (Prototype)")
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Privacy", systemImage: "lock.shield")
                        Text("All processing happens on-device. Your conversations never leave your phone.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Debug Section
                Section("Debug") {
                    if case .downloading(let progress) = viewModel.modelState {
                        HStack {
                            Text("Download Progress")
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .foregroundColor(.secondary)
                        }
                    }

                    if case .error(let message) = viewModel.modelState {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Error")
                                .foregroundColor(.red)
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Button("Retry Loading Model") {
                            Task {
                                await viewModel.loadModel()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        switch viewModel.modelState {
        case .idle:
            return .gray
        case .downloading, .loading:
            return .orange
        case .ready:
            return .green
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch viewModel.modelState {
        case .idle:
            return "Not Loaded"
        case .downloading(let progress):
            return "Downloading (\(Int(progress * 100))%)"
        case .loading:
            return "Loading..."
        case .ready:
            return "Ready"
        case .error:
            return "Error"
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView(viewModel: ChatViewModel(llmService: LLMService()))
}
