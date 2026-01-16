import Foundation

enum SearchIntent {
    case definitelyNeedsSearch    // High confidence - always search
    case probablyNeedsSearch      // Medium confidence - search if online
    case noSearchNeeded           // Use local LLM only
}

struct IntentDetector {

    // MARK: - Detection Patterns

    // DEFINITE triggers - explicit web search requests
    private static let definitePatterns: [String] = [
        "search for",
        "search the web",
        "look up online",
        "google",
        "find online",
        "what's in the news",
        "what is in the news",
        "latest news",
        "current news",
        "recent news",
        "news about",
        "news on"
    ]

    // PROBABLE triggers - temporal/current event indicators
    private static let temporalKeywords: [String] = [
        "today",
        "yesterday",
        "this week",
        "this month",
        "this year",
        "recent",
        "recently",
        "latest",
        "current",
        "currently",
        "now",
        "right now",
        "2024",
        "2025",
        "2026"
    ]

    private static let currentEventPhrases: [String] = [
        "what happened",
        "what's happening",
        "what is happening",
        "who won",
        "who is winning",
        "stock price",
        "weather in",
        "weather for",
        "score of",
        "how much is",
        "exchange rate",
        "price of",
        "breaking news",
        "live update"
    ]

    // NEVER search - personal/conversational/tutorial requests
    private static let noSearchPatterns: [String] = [
        "tell me about yourself",
        "what can you do",
        "help me write",
        "write me",
        "explain to me",
        "explain how",
        "explain what",
        "how do i code",
        "how do i program",
        "summarize this",
        "translate this",
        "translate to",
        "what do you think",
        "in your opinion",
        "can you help me",
        "teach me",
        "tell me a joke",
        "tell me a story"
    ]

    // MARK: - Public API

    static func detectIntent(query: String) -> SearchIntent {
        let lowercased = query.lowercased()

        // Check exclusions first - these don't need web search
        for pattern in noSearchPatterns {
            if lowercased.contains(pattern) {
                return .noSearchNeeded
            }
        }

        // Check definite triggers - always search
        for pattern in definitePatterns {
            if lowercased.contains(pattern) {
                return .definitelyNeedsSearch
            }
        }

        // Check probable triggers (need 2+ indicators for confidence)
        var indicators = 0

        // Check for temporal keywords
        for keyword in temporalKeywords {
            if lowercased.contains(keyword) {
                indicators += 1
                break // Only count once per category
            }
        }

        // Check for current event phrases
        for phrase in currentEventPhrases {
            if lowercased.contains(phrase) {
                indicators += 1
                break
            }
        }

        // Question words at start suggest information-seeking
        let questionStarts = ["what", "who", "where", "when", "why", "how", "is there", "are there", "did", "does", "has", "have"]
        for start in questionStarts {
            if lowercased.hasPrefix(start + " ") || lowercased.hasPrefix(start + "'") {
                indicators += 1
                break
            }
        }

        // If we have 2+ indicators, probably needs search
        if indicators >= 2 {
            return .probablyNeedsSearch
        }

        return .noSearchNeeded
    }

    /// Extract the core search query from user message
    /// Removes filler words and conversational prefixes
    static func extractSearchQuery(from message: String) -> String {
        var query = message

        // Remove common prefixes
        let prefixesToRemove = [
            "can you search for",
            "please search for",
            "search for",
            "look up",
            "find me",
            "tell me about",
            "what is",
            "what are",
            "who is",
            "who are"
        ]

        let lowercased = query.lowercased()
        for prefix in prefixesToRemove {
            if lowercased.hasPrefix(prefix) {
                query = String(query.dropFirst(prefix.count))
                break
            }
        }

        return query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
