//
//  IntentDetector.swift
//  Jubo
//
//  Keyword-based intent detection for routing user queries.
//  Determines whether queries need web search and classifies them
//  for routing to specialized services (weather, sports, etc.).
//

import Foundation

/// Intent classification for web search decisions.
enum SearchIntent {
    /// High confidence - explicit search request, always search
    case definitelyNeedsSearch
    /// Medium confidence - temporal/current event indicators, search if online
    case probablyNeedsSearch
    /// No external data needed - use local LLM only
    case noSearchNeeded
}

/// Query types for routing to specialized data services.
/// Used to bypass web search when dedicated APIs can provide better data.
enum QueryType {
    /// Weather queries - route to WeatherKit for actual weather data
    case weather
    /// Calendar queries - route to EventKit for schedule data
    case calendar
    /// Reminder queries - route to EventKit for reminders
    case reminders
    /// Sports queries - route to sports API for scores/schedules (future)
    case sports
    /// General queries - use web search or LLM knowledge
    case general
}

/// Time range for calendar queries.
enum CalendarTimeRange {
    case today
    case tomorrow
    case thisWeek
    case specific(Date)
}

/// Keyword-based intent detection for query routing.
///
/// This struct provides static methods to:
/// - Detect if a query needs web search (`detectIntent`)
/// - Classify query type for specialized routing (`classifyQueryType`)
/// - Extract search terms from conversational queries (`extractSearchQuery`)
/// - Extract location from weather queries (`extractWeatherLocation`)
struct IntentDetector {

    // MARK: - Detection Patterns

    // DEFINITE triggers - explicit web search requests
    private static let definitePatterns: [String] = [
        "search for",
        "search the web",
        "look up online",
        "look up",
        "google",
        "find online",
        "what's the news",
        "what is the news",
        "what's in the news",
        "what is in the news",
        "latest news",
        "current news",
        "recent news",
        "news about",
        "news on",
        "the news",
        "any news",
        "today's news"
    ]

    // PROBABLE triggers - temporal/current event indicators
    private static let temporalKeywords: [String] = [
        "today",
        "tomorrow",
        "yesterday",
        "next",
        "upcoming",
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
        "2026",
        "2027"
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
        "live update",
        "next game",
        "next match",
        "playing next",
        "schedule",
        "fixture",
        "standings",
        "results"
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

    // MARK: - Query Type Classification

    /// Keywords that indicate a weather-related query.
    /// When detected, query is routed to WeatherKit instead of web search.
    private static let weatherKeywords: [String] = [
        "weather",
        "temperature",
        "forecast",
        "rain",
        "snow",
        "sunny",
        "cloudy",
        "humid",
        "humidity",
        "wind",
        "storm",
        "precipitation"
    ]

    /// Sports-related keywords (for future implementation)
    private static let sportsKeywords: [String] = [
        "score",
        "game",
        "match",
        "standings",
        "fixture",
        "who won",
        "who is winning",
        "playing next",
        "next game",
        "next match"
    ]

    /// Calendar-related keywords.
    /// When detected, query is routed to EventKit for schedule data.
    private static let calendarKeywords: [String] = [
        "schedule",
        "calendar",
        "meeting",
        "meetings",
        "appointment",
        "appointments",
        "event",
        "events",
        "what's on",
        "what is on",
        "do i have",
        "am i free",
        "am i busy",
        "my day",
        "my schedule",
        "my calendar",
        "planned for",
        "happening today",
        "happening tomorrow"
    ]

    /// Reminder-related keywords.
    /// When detected, query is routed to EventKit for reminders.
    private static let reminderKeywords: [String] = [
        "remind me",
        "reminder",
        "reminders",
        "to-do",
        "todo",
        "to do list",
        "task",
        "tasks",
        "don't forget",
        "need to remember",
        "my reminders",
        "pending tasks",
        "what do i need to"
    ]

    /// Classify the type of query for routing to specialized services.
    ///
    /// This enables bypassing web search for queries that can be better served
    /// by dedicated APIs (e.g., WeatherKit for weather, EventKit for calendar).
    ///
    /// - Parameter query: The user's query text
    /// - Returns: QueryType indicating which service should handle the query
    static func classifyQueryType(_ query: String) -> QueryType {
        let lowercased = query.lowercased()

        // Check for reminder queries first (more specific)
        for keyword in reminderKeywords {
            if lowercased.contains(keyword) {
                return .reminders
            }
        }

        // Check for calendar queries
        for keyword in calendarKeywords {
            if lowercased.contains(keyword) {
                return .calendar
            }
        }

        // Check for weather queries
        for keyword in weatherKeywords {
            if lowercased.contains(keyword) {
                return .weather
            }
        }

        // Check for sports queries (for future use)
        for keyword in sportsKeywords {
            if lowercased.contains(keyword) {
                return .sports
            }
        }

        return .general
    }

    /// Extract location from a weather query using regex patterns.
    ///
    /// Handles various query formats:
    /// - "weather in Boston" → "boston"
    /// - "What's the weather like in NYC?" → "nyc"
    /// - "Boston weather tomorrow" → "boston"
    ///
    /// - Parameter query: The weather-related query
    /// - Returns: Extracted location string, or nil if no location found
    static func extractWeatherLocation(from query: String) -> String? {
        let lowercased = query.lowercased()

        // Regex patterns to match various "weather in [location]" formats
        let patterns = [
            "weather (?:in|for|at) ([\\w\\s,]+?)(?:\\?|$|\\.|!|this|today|tomorrow|weekend|week|right|now|currently)",
            "(?:in|for|at) ([\\w\\s,]+?) weather",
            "([\\w\\s,]+?) weather (?:today|tomorrow|this|forecast|right|now)",
            "what(?:'s| is) the weather (?:in|for|at|like in) ([\\w\\s,]+?)(?:\\?|$|\\.|!|right|now|today|tomorrow)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: lowercased) {
                var location = String(lowercased[range])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "?.,!"))

                // Filter out time-related words that might be captured
                let timeWords = ["today", "tomorrow", "weekend", "week", "now", "right now", "right", "this", "the", "like", "currently", "current"]
                for word in timeWords {
                    location = location.replacingOccurrences(of: word, with: "").trimmingCharacters(in: .whitespaces)
                }

                if location.count > 1 {
                    return location
                }
            }
        }

        return nil
    }

    // MARK: - Calendar Time Range Extraction

    /// Extract the time range from a calendar query.
    /// Defaults to today if no time reference found.
    ///
    /// - Parameter query: The calendar-related query
    /// - Returns: CalendarTimeRange indicating when to fetch events
    static func extractCalendarTimeRange(from query: String) -> CalendarTimeRange {
        let lowercased = query.lowercased()

        // Check for "tomorrow"
        if lowercased.contains("tomorrow") {
            return .tomorrow
        }

        // Check for "this week" / "next week" / "week"
        if lowercased.contains("this week") || lowercased.contains("the week") ||
           lowercased.contains("next week") || lowercased.contains("next few days") ||
           lowercased.contains("coming days") || lowercased.contains("coming week") {
            return .thisWeek
        }

        // Default to today
        return .today
    }

    /// Check if a query is asking to create a reminder (vs. just viewing reminders).
    ///
    /// - Parameter query: The reminder-related query
    /// - Returns: True if the query wants to create a new reminder
    static func isReminderCreationQuery(_ query: String) -> Bool {
        let lowercased = query.lowercased()

        let creationPatterns = [
            "remind me to",
            "remind me about",
            "set a reminder",
            "create a reminder",
            "add a reminder",
            "don't let me forget",
            "make sure i"
        ]

        return creationPatterns.contains { lowercased.contains($0) }
    }

    /// Extract the reminder content and optional time from a creation query.
    ///
    /// - Parameter query: The reminder creation query
    /// - Returns: Tuple of (reminder text, optional due date description)
    static func extractReminderDetails(from query: String) -> (title: String, timeHint: String?) {
        var text = query

        // Remove common prefixes
        let prefixes = [
            "remind me to",
            "remind me about",
            "set a reminder to",
            "set a reminder for",
            "create a reminder to",
            "add a reminder to",
            "don't let me forget to",
            "make sure i"
        ]

        let lowercased = text.lowercased()
        for prefix in prefixes {
            if lowercased.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // Try to extract time hint
        var timeHint: String? = nil
        let timePatterns = [
            ("tomorrow", "tomorrow"),
            ("tonight", "tonight"),
            ("this evening", "this evening"),
            ("this afternoon", "this afternoon"),
            ("this morning", "this morning"),
            ("next week", "next week"),
            ("in an hour", "in 1 hour"),
            ("in \\d+ hours?", nil),  // Regex pattern
            ("at \\d+", nil)  // "at 5" or "at 5pm"
        ]

        for (pattern, hint) in timePatterns {
            if text.lowercased().contains(pattern) || (hint == nil && text.range(of: pattern, options: .regularExpression) != nil) {
                timeHint = hint ?? pattern
                // Remove time from title
                if let range = text.range(of: pattern, options: [.caseInsensitive, .regularExpression]) {
                    text = text.replacingCharacters(in: range, with: "").trimmingCharacters(in: .whitespaces)
                }
                break
            }
        }

        return (text, timeHint)
    }
}
