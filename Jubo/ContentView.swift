import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var llmService: LLMService

    var body: some View {
        NavigationStack {
            ConversationListView(llmService: llmService)
                .navigationDestination(for: Conversation.self) { conversation in
                    ChatDetailView(
                        conversation: conversation,
                        llmService: llmService
                    )
                }
        }
    }
}

// MARK: - Chat Detail View

struct ChatDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let conversation: Conversation
    let llmService: LLMService

    @StateObject private var viewModel: ChatViewModel

    init(conversation: Conversation, llmService: LLMService) {
        self.conversation = conversation
        self.llmService = llmService
        _viewModel = StateObject(wrappedValue: ChatViewModel(llmService: llmService))
    }

    var body: some View {
        ChatView(viewModel: viewModel, title: conversation.title)
            .onAppear {
                viewModel.loadConversation(conversation, context: modelContext)
            }
            .onChange(of: conversation.id) { _, _ in
                viewModel.loadConversation(conversation, context: modelContext)
            }
    }
}
