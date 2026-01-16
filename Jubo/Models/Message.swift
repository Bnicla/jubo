import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct Message: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date

    // Web search metadata
    var usedWebSearch: Bool
    var webSources: [String]?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        usedWebSearch: Bool = false,
        webSources: [String]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.usedWebSearch = usedWebSearch
        self.webSources = webSources
    }

    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id &&
        lhs.role == rhs.role &&
        lhs.content == rhs.content &&
        lhs.usedWebSearch == rhs.usedWebSearch
    }
}
