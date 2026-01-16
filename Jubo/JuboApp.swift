import SwiftUI
import SwiftData

@main
struct JuboApp: App {
    @StateObject private var llmService = LLMService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Conversation.self,
            StoredMessage.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(llmService: llmService)
                .task {
                    // Auto-load model on app launch
                    await llmService.loadModel()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
