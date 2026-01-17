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
    @ObservedObject private var userPrefs = UserPreferences.shared
    @Environment(\.dismiss) private var dismiss

    // Web search settings
    @State private var webSearchEnabled = true
    @State private var apiKey = ""
    @State private var searchesThisMonth = 0
    @State private var showingAPIKeyAlert = false
    @State private var showingLocationPicker = false

    private let webSearchCoordinator = WebSearchCoordinator()

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

                Section {
                    Toggle("Enable Web Search", isOn: $webSearchEnabled)
                        .onChange(of: webSearchEnabled) { _, newValue in
                            Task {
                                await webSearchCoordinator.setWebSearchEnabled(newValue)
                            }
                        }

                    if webSearchEnabled {
                        Button {
                            showingAPIKeyAlert = true
                        } label: {
                            HStack {
                                Label("API Key", systemImage: "key")
                                Spacer()
                                Text(apiKey.isEmpty ? "Not Set" : "Configured")
                                    .foregroundColor(apiKey.isEmpty ? .orange : .green)
                            }
                        }
                        .foregroundColor(.primary)

                        HStack {
                            Label("Usage", systemImage: "chart.bar")
                            Spacer()
                            Text("\(searchesThisMonth) / 2000")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Web Search")
                } footer: {
                    Text("Web search allows Jubo to fetch current information from the internet. Queries are anonymized before sending.")
                }

                // MARK: - User Preferences
                Section {
                    Button {
                        showingLocationPicker = true
                    } label: {
                        HStack {
                            Label("Location", systemImage: "location")
                            Spacer()
                            Text(userPrefs.location.isEmpty ? "Not Set" : userPrefs.location)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(.primary)

                    Picker("Temperature", selection: $userPrefs.temperatureUnit) {
                        ForEach(UserPreferences.TemperatureUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }

                    Picker("Time Format", selection: $userPrefs.timeFormat) {
                        ForEach(UserPreferences.TimeFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }

                    Picker("Distance", selection: $userPrefs.distanceUnit) {
                        ForEach(UserPreferences.DistanceUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Location helps Jubo understand local context (sports teams, weather, news).")
                }

                Section("About") {
                    LabeledContent("Version", value: "0.2.0")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Privacy")
                            .font(.headline)
                        Text("All AI processing happens on-device. Web searches are anonymized - personal information is removed before any query leaves your phone.")
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
            .task {
                await loadWebSearchSettings()
            }
            .alert("Brave Search API Key", isPresented: $showingAPIKeyAlert) {
                TextField("API Key", text: $apiKey)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    Task {
                        await webSearchCoordinator.setAPIKey(apiKey)
                    }
                }
            } message: {
                Text("Get a free API key at api.search.brave.com (2000 searches/month)")
            }
            .sheet(isPresented: $showingLocationPicker) {
                LocationSearchView(selectedLocation: $userPrefs.location)
            }
        }
    }

    private func loadWebSearchSettings() async {
        webSearchEnabled = await webSearchCoordinator.isWebSearchEnabled()
        apiKey = await webSearchCoordinator.getAPIKey() ?? ""
        searchesThisMonth = await webSearchCoordinator.searchesThisMonth
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
