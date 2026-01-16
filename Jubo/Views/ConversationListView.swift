import SwiftUI
import SwiftData

struct ConversationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @ObservedObject var llmService: LLMService
    @State private var showingSettings = false
    @State private var conversationToRename: Conversation?
    @State private var newTitle = ""
    @State private var navigateToConversation: Conversation?

    var body: some View {
        List {
            // New Chat Button
            Button {
                createNewConversation()
            } label: {
                Label("New Chat", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .disabled(!llmService.isReady)

            // Model Status
            if !llmService.isReady {
                modelStatusSection
            }

            // Conversations
            if !conversations.isEmpty {
                Section("Recent") {
                    ForEach(conversations) { conversation in
                        NavigationLink(value: conversation) {
                            ConversationRow(conversation: conversation)
                        }
                        .contextMenu {
                            Button {
                                conversationToRename = conversation
                                newTitle = conversation.title
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                deleteConversation(conversation)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteConversation(conversation)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Jubo")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(llmService: llmService)
        }
        .alert("Rename Chat", isPresented: .init(
            get: { conversationToRename != nil },
            set: { if !$0 { conversationToRename = nil } }
        )) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) {
                conversationToRename = nil
            }
            Button("Save") {
                if let conversation = conversationToRename {
                    conversation.title = newTitle
                    try? modelContext.save()
                }
                conversationToRename = nil
            }
        }
        .navigationDestination(item: $navigateToConversation) { conversation in
            ChatDetailView(conversation: conversation, llmService: llmService)
        }
    }

    // MARK: - Model Status Section

    @ViewBuilder
    private var modelStatusSection: some View {
        Section {
            switch llmService.modelState {
            case .idle:
                HStack {
                    Text("Model not loaded")
                    Spacer()
                    Button("Load") {
                        Task {
                            await llmService.loadModel()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Downloading model...")
                        .font(.subheadline)
                    ProgressView(value: progress)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .loading:
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading model...")
                        .foregroundColor(.secondary)
                }

            case .ready:
                EmptyView()

            case .error(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Error loading model", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task {
                            await llmService.loadModel()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Actions

    private func createNewConversation() {
        let conversation = Conversation()
        modelContext.insert(conversation)
        try? modelContext.save()
        navigateToConversation = conversation
    }

    private func deleteConversation(_ conversation: Conversation) {
        modelContext.delete(conversation)
        try? modelContext.save()
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        Text(conversation.title)
            .font(.body)
            .lineLimit(1)
    }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    @ObservedObject var llmService: LLMService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Model") {
                    LabeledContent("Model", value: llmService.modelInfo)
                    LabeledContent("Status", value: statusText)

                    if llmService.tokensPerSecond > 0 {
                        LabeledContent("Speed", value: String(format: "%.1f tok/s", llmService.tokensPerSecond))
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Privacy")
                            .font(.headline)
                        Text("All processing happens on-device. Your conversations never leave your phone.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var statusText: String {
        switch llmService.modelState {
        case .idle: return "Not Loaded"
        case .downloading(let p): return "Downloading (\(Int(p * 100))%)"
        case .loading: return "Loading..."
        case .ready: return "Ready"
        case .error: return "Error"
        }
    }
}
