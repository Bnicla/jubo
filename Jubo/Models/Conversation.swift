import Foundation
import SwiftData

@Model
final class Conversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \StoredMessage.conversation)
    var messages: [StoredMessage] = []

    init(title: String = "New Chat") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Generate a title from the first user message
    func generateTitle(from firstMessage: String) {
        let trimmed = firstMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 40 {
            title = String(trimmed.prefix(40)) + "..."
        } else {
            title = trimmed
        }
    }
}

@Model
final class StoredMessage {
    var id: UUID
    var role: String // "user", "assistant", "system"
    var content: String
    var timestamp: Date

    // Web search metadata
    var usedWebSearch: Bool = false
    var webSourcesData: Data?  // JSON encoded [String]

    var conversation: Conversation?

    init(role: MessageRole, content: String) {
        self.id = UUID()
        self.role = role.rawValue
        self.content = content
        self.timestamp = Date()
        self.usedWebSearch = false
        self.webSourcesData = nil
    }

    /// Get/set web sources as string array
    var webSources: [String]? {
        get {
            guard let data = webSourcesData else { return nil }
            return try? JSONDecoder().decode([String].self, from: data)
        }
        set {
            webSourcesData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Convert to the Message struct used by the view model
    func toMessage() -> Message {
        Message(
            id: id,
            role: MessageRole(rawValue: role) ?? .user,
            content: content,
            timestamp: timestamp,
            usedWebSearch: usedWebSearch,
            webSources: webSources
        )
    }

    /// Create from a Message struct
    static func from(_ message: Message) -> StoredMessage {
        let stored = StoredMessage(role: message.role, content: message.content)
        stored.id = message.id
        stored.timestamp = message.timestamp
        stored.usedWebSearch = message.usedWebSearch
        stored.webSources = message.webSources
        return stored
    }
}
