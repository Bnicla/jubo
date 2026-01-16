import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    var title: String = "Jubo"
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            messagesScrollView

            Divider()

            // Input area
            inputArea
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        viewModel.clearChat()
                    } label: {
                        Label("Clear Chat", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Messages Scroll View

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Model status banner if not ready
                    if !viewModel.isModelReady {
                        modelStatusBanner
                    }

                    // Welcome message if no messages
                    if viewModel.messages.isEmpty && viewModel.isModelReady {
                        welcomeMessage
                    }

                    // Messages
                    ForEach(viewModel.messages) { message in
                        MessageBubble(
                            message: message,
                            isGenerating: viewModel.isGenerating &&
                                message.id == viewModel.messages.last?.id &&
                                message.role == .assistant
                        )
                        .id(message.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.messages.last?.content) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = viewModel.messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Model Status Banner

    private var modelStatusBanner: some View {
        VStack(spacing: 12) {
            switch viewModel.modelState {
            case .idle:
                Text("Tap to load the AI model")
                    .foregroundColor(.secondary)
                Button("Load Model") {
                    Task {
                        await viewModel.loadModel()
                    }
                }
                .buttonStyle(.borderedProminent)

            case .downloading(let progress):
                VStack(spacing: 8) {
                    Text("Downloading model...")
                        .font(.headline)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 200)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .loading:
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading model...")
                        .foregroundColor(.secondary)
                }

            case .ready:
                EmptyView()

            case .error(let message):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Failed to load model")
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task {
                            await viewModel.loadModel()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }

    // MARK: - Welcome Message

    private var welcomeMessage: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Welcome to Jubo")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your private AI assistant running entirely on-device. No internet required.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 8) {
                suggestionButton("What can you help me with?")
                suggestionButton("Tell me a short joke")
                suggestionButton("Explain quantum computing simply")
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 40)
    }

    private func suggestionButton(_ text: String) -> some View {
        Button {
            viewModel.inputText = text
            Task {
                await viewModel.sendMessage()
            }
        } label: {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Message", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...5)
                .focused($isInputFocused)
                .disabled(!viewModel.isModelReady || viewModel.isGenerating)
                .onSubmit {
                    if !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task {
                            await viewModel.sendMessage()
                        }
                    }
                }

            Button {
                Task {
                    await viewModel.sendMessage()
                }
            } label: {
                Image(systemName: viewModel.isGenerating ? "stop.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(sendButtonColor)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    private var canSend: Bool {
        viewModel.isModelReady &&
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !viewModel.isGenerating
    }

    private var sendButtonColor: Color {
        canSend ? .blue : .gray
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ChatView(viewModel: ChatViewModel(llmService: LLMService()))
    }
}
