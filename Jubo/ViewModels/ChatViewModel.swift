import Foundation
import SwiftData
import Combine

@MainActor
class ChatViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isGenerating: Bool = false
    @Published var error: String?

    // MARK: - Dependencies

    let llmService: LLMService
    private var modelContext: ModelContext?
    private var conversation: Conversation?

    // MARK: - Computed Properties

    var modelState: ModelState {
        llmService.modelState
    }

    var isModelReady: Bool {
        llmService.isReady
    }

    var tokensPerSecond: Double {
        llmService.tokensPerSecond
    }

    var modelInfo: String {
        llmService.modelInfo
    }

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(llmService: LLMService) {
        self.llmService = llmService

        // Observe LLM service changes
        llmService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// Load a conversation and its messages
    func loadConversation(_ conversation: Conversation, context: ModelContext) {
        self.conversation = conversation
        self.modelContext = context

        // Load messages from the conversation
        messages = conversation.messages
            .sorted { $0.timestamp < $1.timestamp }
            .map { $0.toMessage() }

        // Reset the LLM session for the new conversation
        llmService.resetSession()
    }

    /// Load the LLM model
    func loadModel() async {
        await llmService.loadModel()
    }

    /// Send a message and generate a response
    func sendMessage() async {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        guard isModelReady else { return }
        guard !isGenerating else { return }

        // Clear input
        let userText = trimmedText
        inputText = ""

        // Add user message
        let userMessage = Message(role: .user, content: userText)
        messages.append(userMessage)
        saveMessage(userMessage)

        // Update conversation title if this is the first message
        if let conversation = conversation, conversation.messages.count == 1 {
            conversation.generateTitle(from: userText)
            saveContext()
        }

        // Add placeholder for assistant response
        let assistantMessage = Message(role: .assistant, content: "")
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1

        // Start generation
        isGenerating = true
        error = nil

        do {
            // Get the context (all messages except the empty assistant placeholder)
            let context = Array(messages.dropLast())

            // Stream tokens from the LLM
            for try await token in llmService.generate(messages: context) {
                // Append token to the assistant message
                messages[assistantIndex].content += token
            }

            // Save the completed assistant message
            saveMessage(messages[assistantIndex])

        } catch {
            // Handle error
            self.error = error.localizedDescription
            // Remove empty assistant message on error
            if messages[assistantIndex].content.isEmpty {
                messages.remove(at: assistantIndex)
            }
        }

        isGenerating = false
    }

    /// Clear all messages (for current conversation)
    func clearChat() {
        messages.removeAll()
        error = nil

        // Delete messages from the conversation
        if let conversation = conversation {
            for message in conversation.messages {
                modelContext?.delete(message)
            }
            saveContext()
        }

        // Reset the LLM session
        llmService.resetSession()
    }

    /// Stop current generation (for future implementation)
    func stopGeneration() {
        // TODO: Implement generation cancellation
        isGenerating = false
    }

    // MARK: - Private Methods

    private func saveMessage(_ message: Message) {
        guard let conversation = conversation, let context = modelContext else { return }

        let storedMessage = StoredMessage.from(message)
        storedMessage.conversation = conversation
        context.insert(storedMessage)

        // Update conversation timestamp
        conversation.updatedAt = Date()

        saveContext()
    }

    private func saveContext() {
        try? modelContext?.save()
    }
}
