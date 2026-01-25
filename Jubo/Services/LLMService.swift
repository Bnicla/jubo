//
//  LLMService.swift
//  Jubo
//
//  Core LLM inference service using Apple's MLX framework.
//  Handles model loading, token streaming, and intent classification.
//
//  Supported models (tried in order with automatic fallback):
//  - SmolLM3 3B (4-bit) - Best quality/speed balance
//  - Qwen2.5 3B (4-bit) - Good alternative
//  - Llama 3.2 1B (4-bit) - Fastest, smallest
//

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

    // Model IDs to try in order (fallback if first fails)
    private let modelIds = [
        "mlx-community/SmolLM3-3B-Instruct-4bit",
        "mlx-community/Qwen2.5-3B-Instruct-4bit",
        "mlx-community/Llama-3.2-1B-Instruct-4bit"  // Last resort fallback
    ]
    private var currentModelIndex = 0

    // Generation parameters - tuned for SmolLM3
    // SmolLM3 recommends: temperature=0.6, top_p=0.95
    // maxTokens reduced to encourage brevity (model can still stop earlier)
    private let generateParameters = GenerateParameters(
        maxTokens: 150,
        temperature: 0.6,
        topP: 0.95
    )

    // Prompt builder for adaptive system prompts
    private let promptBuilder = AdaptivePromptBuilder()

    // System prompt - built dynamically from preferences and learned memory
    private var systemPrompt: String {
        promptBuilder.buildSystemPrompt()
    }

    // MARK: - Public Methods

    /// Load the LLM model from HuggingFace (tries multiple models with fallback)
    func loadModel() async {
        guard modelState != .ready else { return }

        // Set a conservative cache limit to help memory-constrained devices
        // This limits how much "recycled" buffer memory MLX keeps around
        Memory.cacheLimit = 100 * 1024 * 1024  // 100MB cache limit
        print("[LLM] Set memory cache limit to 100MB")

        // Try each model in order until one succeeds
        for (index, modelId) in modelIds.enumerated() {
            currentModelIndex = index
            modelState = .downloading(progress: 0)
            print("[LLM] Trying model: \(modelId)")

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
                print("[LLM] Successfully loaded: \(modelId)")
                return  // Success - exit the loop

            } catch {
                print("[LLM] Failed to load \(modelId): \(error)")
                // Continue to next model if available
                if index == modelIds.count - 1 {
                    // Last model also failed
                    modelState = .error("All models failed to load")
                }
            }
        }
    }

    /// Generate a response for the given messages
    /// - Parameters:
    ///   - messages: The conversation messages
    ///   - searchContext: Optional web search context to prepend to the prompt
    ///   - detailLevel: Expected response detail level (brief vs detailed)
    func generate(
        messages: [Message],
        searchContext: String? = nil,
        detailLevel: ResponseDetailLevel = .detailed
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.performGeneration(
                    messages: messages,
                    searchContext: searchContext,
                    detailLevel: detailLevel,
                    continuation: continuation
                )
            }
        }
    }

    // MARK: - Private Methods

    private func performGeneration(
        messages: [Message],
        searchContext: String?,
        detailLevel: ResponseDetailLevel,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        guard var session = chatSession, let container = modelContainer else {
            continuation.finish(throwing: LLMServiceError.modelNotLoaded)
            return
        }

        // Get the last user message
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else {
            continuation.finish(throwing: LLMServiceError.generationFailed("No user message found"))
            return
        }

        // If using web search, reset session to free GPU memory from accumulated history
        // This prevents memory overflow when adding search context
        if searchContext != nil {
            // Sync GPU and wait briefly before creating new session
            // This ensures classifier sessions have fully released GPU resources
            Stream.gpu.synchronize()
            try? await Task.sleep(for: .milliseconds(100))

            // Adjust maxTokens based on expected detail level
            let maxTokens: Int
            switch detailLevel {
            case .brief:
                maxTokens = 100   // Short, direct answer
            case .detailed:
                maxTokens = 200   // More room for detailed response
            }

            // Build prompt with detail-level specific instructions
            let searchPrompt = promptBuilder.buildSystemPrompt(detailLevel: detailLevel)

            // Create fresh session and update instance variable
            let newSession = ChatSession(
                container,
                instructions: searchPrompt,
                generateParameters: GenerateParameters(
                    maxTokens: maxTokens,
                    temperature: 0.3,  // Lower for web search - stick to facts
                    topP: 0.95
                )
            )
            session = newSession
            chatSession = newSession  // Update instance variable too
            print("[LLM] Web search response - maxTokens: \(maxTokens) (\(detailLevel == .brief ? "brief" : "detailed"))")
        }

        // Build the prompt - use search context if provided, otherwise just the user message
        let prompt: String
        if let context = searchContext {
            // Search context already includes the user's question
            prompt = context
        } else {
            prompt = lastUserMessage.content
        }

        // Track generation stats
        let startTime = Date()
        var tokenCount = 0

        do {
            // Stream the response
            for try await chunk in session.streamResponse(to: prompt) {
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
        let modelId = modelIds[currentModelIndex]
        // Extract friendly name from model ID
        if modelId.contains("SmolLM3") {
            return "SmolLM3 3B (4-bit)"
        } else if modelId.contains("Qwen2.5-3B") {
            return "Qwen2.5 3B (4-bit)"
        } else if modelId.contains("Llama-3.2-1B") {
            return "Llama 3.2 1B (4-bit)"
        } else {
            return modelId.components(separatedBy: "/").last ?? modelId
        }
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

    // MARK: - Intent Classification (Orchestrator Foundation)

    /// Classify if a query needs web search (real-time/current information)
    /// Returns true if web search would help answer the query
    func needsWebSearch(query: String) async -> Bool {
        guard let container = modelContainer else { return false }

        // Create a minimal session for classification
        let classifierSession = ChatSession(
            container,
            instructions: "You are a classifier. Only respond with YES or NO.",
            generateParameters: GenerateParameters(
                maxTokens: 8,
                temperature: 0.1,
                topP: 0.9
            )
        )

        // Few-shot prompt for better classification
        let prompt = """
            Does this question require current internet data to answer?

            "What is 2+2?" → NO
            "Explain photosynthesis" → NO
            "What's the weather today?" → YES
            "What's the temperature tomorrow?" → YES
            "Latest news about Apple" → YES
            "Next Lakers game?" → YES
            "How do I cook pasta?" → NO

            "\(query)" →
            """

        var response = ""
        do {
            for try await token in classifierSession.streamResponse(to: prompt) {
                response += token
                // Stop as soon as we see YES or NO
                let upper = response.uppercased()
                if upper.contains("YES") || upper.contains("NO") { break }
            }
        } catch {
            print("[LLM] Intent classification failed: \(error)")
            // On error, cleanup and return false (don't search)
            await cleanupGPUMemory()
            return false
        }

        let needsSearch = response.uppercased().contains("YES")
        print("[LLM] Intent classification: '\(query)' → \(needsSearch ? "NEEDS SEARCH" : "NO SEARCH")")

        // Note: Don't cleanup here - classifyResponseDetail() may run immediately after
        // Cleanup happens after all classification is complete

        return needsSearch
    }

    /// Classify expected response detail level
    /// Returns .brief for single-fact answers, .detailed for multi-part answers
    func classifyResponseDetail(query: String) async -> ResponseDetailLevel {
        guard let container = modelContainer else { return .detailed }

        let classifierSession = ChatSession(
            container,
            instructions: "You are a classifier. Only respond with BRIEF or DETAILED.",
            generateParameters: GenerateParameters(
                maxTokens: 8,
                temperature: 0.1,
                topP: 0.9
            )
        )

        let prompt = """
            Does this question need a brief answer (single fact) or detailed answer (multiple facts)?

            "When is the next Lakers game?" → BRIEF
            "What time does the store close?" → BRIEF
            "Who won the Super Bowl?" → BRIEF
            "What's the weather like?" → DETAILED
            "Tell me about the weather today" → DETAILED
            "What's happening in the news?" → DETAILED
            "How is the traffic?" → DETAILED
            "What should I wear today?" → DETAILED

            "\(query)" →
            """

        var response = ""
        do {
            for try await token in classifierSession.streamResponse(to: prompt) {
                response += token
                let upper = response.uppercased()
                if upper.contains("BRIEF") || upper.contains("DETAILED") { break }
            }
        } catch {
            print("[LLM] Response detail classification failed: \(error)")
            await cleanupGPUMemory()
            return .detailed  // Default to detailed on error
        }

        let isBrief = response.uppercased().contains("BRIEF")
        print("[LLM] Response detail: '\(query)' → \(isBrief ? "BRIEF" : "DETAILED")")

        await cleanupGPUMemory()
        return isBrief ? .brief : .detailed
    }

    /// Force GPU synchronization (safe cleanup that doesn't invalidate model data)
    private func cleanupGPUMemory() async {
        // Synchronize forces all pending GPU operations to complete
        Stream.gpu.synchronize()

        // Note: We intentionally do NOT call Memory.clearCache() here.
        // Clearing the cache while the model is active can cause GPU page faults
        // because model weights and intermediate tensors may still be referenced.
        // The cache will naturally be managed by MLX's memory allocator.

        let snapshot = Memory.snapshot()
        print("[LLM] GPU sync complete - Active: \(snapshot.activeMemory / 1024 / 1024)MB, Cache: \(snapshot.cacheMemory / 1024 / 1024)MB")
    }
}
