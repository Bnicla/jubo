//
//  AdaptivePromptBuilder.swift
//  Jubo
//
//  Builds the system prompt by combining:
//  - Base instructions (tool-first, no personality)
//  - User preferences (location, units)
//  - Learned memories (facts about the user)
//  - Adaptive style hints (from interaction patterns)
//

import Foundation

/// Builds adaptive system prompts based on user context and learned preferences.
///
/// The prompt follows these principles:
/// - Tool-first: No first-person pronouns, no personality projection
/// - Anti-sycophancy: Never open with praise or validation
/// - Adaptive length: Adjusts verbosity based on learned patterns
/// - Accuracy-focused: Admits uncertainty, never fabricates
///
/// Usage:
/// ```swift
/// let builder = AdaptivePromptBuilder()
/// let prompt = await builder.buildSystemPrompt()
/// ```
struct AdaptivePromptBuilder {

    // MARK: - Base System Prompt

    /// Core instructions for the assistant.
    /// Written in third-person to avoid personality projection.
    private let basePrompt = """
        Jubo is a local assistant running on the user's device.

        CORE RULES:
        • Start with the answer. No greetings, no restating the question.
        • Never open with praise ("Great question", "That's interesting").
        • Never use filler phrases ("Absolutely!", "Of course!", "Certainly!").
        • When uncertain, say "Not sure" rather than guessing.

        RESPONSE LENGTH - THIS IS CRITICAL:
        Default to SHORT. Only expand when explicitly needed.

        ONE SENTENCE OR LESS for:
        • Yes/no questions → "Yes." or "No, because X."
        • Factual lookups → "Paris." / "72°F and sunny." / "3:45 PM."
        • Simple calculations → "30."
        • Single-fact questions → Just the fact.

        TWO TO THREE SENTENCES for:
        • "What is X?" → Brief definition, one clarifying detail.
        • Recommendations → Answer plus brief reasoning.
        • Weather/calendar results → Key info plus one relevant detail.

        LONGER ONLY WHEN:
        • User explicitly says "explain", "detail", "walk me through", "tell me more"
        • "How does X work?" or "Why does X happen?"
        • "Compare X and Y" or "pros and cons"
        • Complex multi-part questions
        • Writing assistance (match the requested output length)

        EXAMPLES OF CORRECT LENGTH:
        Q: "Is it raining?" → "No, it's sunny."
        Q: "What's 15% of 200?" → "30."
        Q: "Capital of France?" → "Paris."
        Q: "What time is my meeting?" → "2 PM with Sarah."
        Q: "What is photosynthesis?" → "The process plants use to convert sunlight, water, and CO2 into glucose and oxygen."
        Q: "Explain how photosynthesis works" → [Detailed multi-paragraph explanation - user asked for explanation]

        ACCURACY:
        • For current events, weather, sports, or live data: use provided context only.
        • Never fabricate sources, statistics, dates, or quotes.
        • If asked about real-time data and none is provided, say so briefly.

        FORMATTING:
        • Default to plain prose. Skip markdown unless it helps.
        • Use bullet points only for 3+ unordered items.
        • Use numbered lists only for sequential steps.
        """

    // MARK: - Tool Definitions

    /// Available tools the model can invoke.
    private let toolDefinitions = """
        AVAILABLE TOOLS:
        You can request real-time data using these tools. Output the tool tag when needed.

        weather - Current conditions or forecast
          Use for: "What's the weather?", "Will it rain tomorrow?", "Weather in Boston"
          Format: <tool>weather|location=CITY</tool>
          Examples: <tool>weather|location=Boston</tool>, <tool>weather|location=New York</tool>

        calendar - User's schedule
          Use for: "What's on my calendar?", "Do I have meetings today?", "What's tomorrow look like?"
          Format: <tool>calendar|range=today</tool> or <tool>calendar|range=tomorrow</tool> or <tool>calendar|range=this_week</tool>

        reminders - User's tasks and reminders
          Use for: "What are my reminders?", "Show my tasks", "What do I need to do?"
          Format: <tool>reminders|filter=today</tool> or <tool>reminders|filter=all</tool>
          To CREATE a reminder: "Remind me to X" - use <tool>reminder_create|title=X</tool>
          With time: <tool>reminder_create|title=X|due=tomorrow</tool>

        sports - Live scores and results
          Use for: "Did the Lakers win?", "Score of the game", standings, schedules
          Format: <tool>sports|league=nba|team=lakers</tool>
          Leagues: nba, nfl, mlb, nhl, premier_league, champions_league, la_liga, mls

        search - Web search for current info
          Use for: Current events, news, prices, recent information
          Format: <tool>search|query=YOUR QUERY</tool>

        WHEN TO USE TOOLS:
        • Weather questions → weather tool
        • Calendar/schedule questions → calendar tool
        • Reminders/tasks questions → reminders tool
        • "Remind me to..." → reminder_create tool
        • Live sports scores, game results → sports tool
        • Current news, recent events → search tool

        WHEN NOT TO USE TOOLS (answer directly):
        • General knowledge: "What is photosynthesis?", "Capital of France?"
        • Definitions: "What does 'ephemeral' mean?"
        • How-to: "How do I write a for loop?"
        • Math: "What's 15% of 200?"
        • Writing help: "Help me write an email"
        • Historical facts: "When was the Eiffel Tower built?"

        If you use a tool, output the tag at the START of your response.
        """

    // MARK: - Banned Patterns

    /// Response openers that should never be used.
    /// These are checked during development/testing.
    static let bannedOpeners = [
        // Sycophantic praise
        "Great question",
        "That's a great question",
        "Excellent question",
        "Good question",
        "What a fascinating",
        "That's fascinating",
        "That's interesting",
        "Interesting question",
        "Good thinking",
        "Great thinking",
        // Filler affirmations
        "Absolutely!",
        "Absolutely,",
        "Of course!",
        "Of course,",
        "Certainly!",
        "Certainly,",
        "Sure thing",
        "Sure!",
        "Sure,",
        "Happy to help",
        "I'd be happy to",
        "I'd love to",
        "Let me help you",
        // Verbose preambles
        "Based on",
        "According to",
        "I can help you with that",
        "I can answer that",
        "I can tell you",
        "Let me",
        "I'll",
        "Here's what I found",
        "Here's the answer",
        "The answer is",
        "To answer your question",
    ]

    // MARK: - Public API

    /// Build the complete system prompt with all context layers.
    @MainActor
    func buildSystemPrompt() -> String {
        var sections: [String] = [basePrompt]

        // Add tool definitions
        sections.append(toolDefinitions)

        // Add user preferences (location, units, etc.)
        let prefsContext = buildPreferencesContext()
        if !prefsContext.isEmpty {
            sections.append(prefsContext)
        }

        // Add learned memories
        let memoryContext = buildMemoryContext()
        if !memoryContext.isEmpty {
            sections.append(memoryContext)
        }

        // Add adaptive style hints (only if strong signal)
        let styleHints = buildStyleHints()
        if !styleHints.isEmpty {
            sections.append(styleHints)
        }

        return sections.joined(separator: "\n\n")
    }

    /// Build prompt for a specific response detail level.
    @MainActor
    func buildSystemPrompt(detailLevel: ResponseDetailLevel) -> String {
        var prompt = buildSystemPrompt()

        // Add detail-level specific instructions
        switch detailLevel {
        case .brief:
            prompt += """


                [MODE: BRIEF]
                This is a simple factual query. Give the shortest possible answer.
                • One sentence maximum
                • Just the fact, no context
                • No "here's what I found" preamble
                Example: "Lakers won 112-108" not "Based on the latest scores, the Lakers defeated their opponents with a final score of 112-108 in what was an exciting game..."
                """
        case .detailed:
            prompt += """


                [MODE: DETAILED]
                This query warrants more context. Provide a helpful answer with relevant details.
                • 2-4 sentences typical
                • Include useful context
                • Still no unnecessary filler
                """
        }

        return prompt
    }

    // MARK: - Context Builders

    /// Build context from UserPreferences (explicit settings).
    private func buildPreferencesContext() -> String {
        let prefs = UserPreferences.shared
        var parts: [String] = []

        if !prefs.location.isEmpty {
            parts.append("User location: \(prefs.location). Use for local context (sports teams, weather, news).")
        }

        parts.append("Temperature: \(prefs.temperatureUnit.rawValue)")
        parts.append("Time format: \(prefs.timeFormat.rawValue)")
        parts.append("Distance: \(prefs.distanceUnit == .metric ? "metric (km)" : "imperial (miles)")")

        if !prefs.customContext.isEmpty {
            parts.append("Additional context: \(prefs.customContext)")
        }

        guard !prefs.location.isEmpty || !prefs.customContext.isEmpty else {
            // Only include if there's meaningful custom context
            return ""
        }

        return "[USER PREFERENCES]\n" + parts.joined(separator: "\n")
    }

    /// Build context from learned memories.
    @MainActor
    private func buildMemoryContext() -> String {
        let memory = UserMemory.shared
        let facts = memory.relevantFacts(limit: 5)

        guard !facts.isEmpty else { return "" }

        var lines = ["[LEARNED ABOUT USER]"]
        for fact in facts {
            lines.append("• \(fact.content)")
        }

        return lines.joined(separator: "\n")
    }

    /// Build style adaptation hints from interaction patterns.
    /// Only adds hints for strong signals to avoid overriding default brevity.
    @MainActor
    private func buildStyleHints() -> String {
        let patterns = UserMemory.shared.patterns
        var hints: [String] = []

        // Require more interactions before adapting (avoid premature adaptation)
        guard patterns.totalInteractions >= 10 else { return "" }

        // Only note if user explicitly prefers MORE detail (rare)
        // Default is already concise, so we don't need to reinforce that
        if let prefersConcise = patterns.prefersConcise {
            if !prefersConcise && patterns.expansionRequests >= 5 {
                // Only if user has asked for more detail multiple times
                hints.append("User has asked for more detail several times. Provide slightly more context when relevant.")
            }
            // Note: We do NOT add "be concise" hint - that's already the default
        }

        // Accuracy emphasis - this is safe to add
        if patterns.valuesAccuracy {
            hints.append("User values accuracy. Acknowledge uncertainty rather than guessing.")
        }

        guard !hints.isEmpty else { return "" }

        return "[STYLE NOTE]\n" + hints.joined(separator: "\n")
    }

    // MARK: - Validation (Development)

    /// Check if a response starts with a banned opener.
    /// Used during development/testing to catch sycophantic patterns.
    static func containsBannedOpener(_ response: String) -> String? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        for banned in bannedOpeners {
            if lowercased.hasPrefix(banned.lowercased()) {
                return banned
            }
        }

        return nil
    }
}
