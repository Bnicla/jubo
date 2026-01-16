import Foundation
import MLX
import MLXLLM
import MLXLMCommon

enum LLMServiceError: LocalizedError {
    case modelNotLoaded
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Model is not loaded. Please wait for the model to download and load."
        case .generationFailed(let message):
            return "Generation failed: \(message)"
        }
    }
}

enum ModelState: Equatable {
    case idle
    case downloading(progress: Double)
    case loading
    case ready
    case error(String)

    static func == (lhs: ModelState, rhs: ModelState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.ready, .ready):
            return true
        case (.downloading(let p1), .downloading(let p2)):
            return p1 == p2
        case (.error(let e1), .error(let e2)):
            return e1 == e2
        default:
            return false
        }
    }
}

@MainActor
class LLMService: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var modelState: ModelState = .idle
    @Published private(set) var tokensPerSecond: Double = 0

    // MARK: - Private Properties

    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?

    // Model ID - using Llama 3.2 1B 4-bit for iPhone 14 compatibility
    private let modelId = "mlx-community/Llama-3.2-1B-Instruct-4bit"

    // Generation parameters
    private let generateParameters = GenerateParameters(
        maxTokens: 512,
        temperature: 0.7,
        topP: 0.9
    )

    // System prompt
    private let systemPrompt = """
        You are Jubo, a helpful AI assistant running entirely on-device. \
        You are private, fast, and always available offline. \
        Keep your responses concise and helpful.
        """

    // MARK: - Public Methods

    /// Load the LLM model from HuggingFace
    func loadModel() async {
        guard modelState != .ready else { return }

        modelState = .downloading(progress: 0)

        do {
            // Load the model with progress tracking
            let container = try await loadModelContainer(id: modelId) { progress in
                Task { @MainActor in
                    self.modelState = .downloading(progress: progress.fractionCompleted)
                }
            }

            self.modelContainer = container

            // Create a chat session with the model
            self.chatSession = ChatSession(
                container,
                instructions: systemPrompt,
                generateParameters: generateParameters
            )

            modelState = .ready
            print("Model loaded successfully")

        } catch {
            modelState = .error(error.localizedDescription)
            print("Failed to load model: \(error)")
        }
    }

    /// Generate a response for the given messages
    func generate(messages: [Message]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.performGeneration(messages: messages, continuation: continuation)
            }
        }
    }

    // MARK: - Private Methods

    private func performGeneration(
        messages: [Message],
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        guard let chatSession = chatSession else {
            continuation.finish(throwing: LLMServiceError.modelNotLoaded)
            return
        }

        // Get the last user message
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else {
            continuation.finish(throwing: LLMServiceError.generationFailed("No user message found"))
            return
        }

        // Track generation stats
        let startTime = Date()
        var tokenCount = 0

        do {
            // Stream the response
            for try await chunk in chatSession.streamResponse(to: lastUserMessage.content) {
                tokenCount += 1
                continuation.yield(chunk)
            }

            // Calculate tokens per second
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > 0 {
                self.tokensPerSecond = Double(tokenCount) / elapsed
            }

            continuation.finish()

        } catch {
            continuation.finish(throwing: error)
        }
    }

    /// Check if model is ready for generation
    var isReady: Bool {
        modelState == .ready
    }

    /// Get model info string
    var modelInfo: String {
        "Llama 3.2 1B Instruct (4-bit)"
    }

    /// Reset the chat session (for new conversations)
    func resetSession() {
        guard let container = modelContainer else { return }
        chatSession = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: generateParameters
        )
    }
}
