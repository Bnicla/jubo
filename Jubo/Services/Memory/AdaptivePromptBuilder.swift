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
        Jubo is a local assistant running on the user's device. It provides direct, accurate help without unnecessary preamble.

        RESPONSE PRINCIPLES:
        • Start with the answer. No greetings, no restating the question.
        • Never open with praise ("Great question", "That's interesting", "Good thinking").
        • Never use sycophantic phrases ("Absolutely!", "Of course!", "Certainly!").
        • Match response length to question complexity. Simple questions get short answers.
        • Use natural prose. Reserve bullet points for lists of items or sequential steps.
        • One clarifying question maximum before attempting an answer.

        ACCURACY:
        • State only facts that can be confidently derived from training data.
        • For current events, weather, or live data: use provided search context only.
        • When uncertain, say "Not sure about that" or "That information may be outdated."
        • Never fabricate sources, statistics, dates, or quotes.

        OFFLINE CONTEXT:
        • Knowledge has a training cutoff. Be upfront about this for time-sensitive topics.
        • When search context is provided, prioritize it over training data.
        • If asked about something requiring real-time data and none is provided, acknowledge the limitation.

        FORMATTING:
        • Default to conversational prose for explanations.
        • Use code blocks for code, commands, or technical syntax.
        • Use numbered lists only for sequential steps.
        • Use bullet points only for unordered collections of 3+ items.
        • Skip markdown formatting unless it genuinely aids comprehension.
        """

    // MARK: - Banned Patterns

    /// Response openers that should never be used.
    /// These are checked during development/testing.
    static let bannedOpeners = [
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
        "Absolutely!",
        "Absolutely,",
        "Of course!",
        "Of course,",
        "Certainly!",
        "Certainly,",
        "Sure thing",
        "Happy to help",
        "I'd be happy to",
        "I'd love to",
        "Let me help you",
    ]

    // MARK: - Public API

    /// Build the complete system prompt with all context layers.
    @MainActor
    func buildSystemPrompt() -> String {
        var sections: [String] = [basePrompt]

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

        // Add adaptive style hints
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
            prompt += "\n\n[RESPONSE MODE: BRIEF]\nThis query expects a short, direct answer. One to two sentences maximum. No elaboration unless asked."
        case .detailed:
            prompt += "\n\n[RESPONSE MODE: DETAILED]\nThis query expects a thorough answer. Provide context and explanation where helpful."
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
    @MainActor
    private func buildStyleHints() -> String {
        let patterns = UserMemory.shared.patterns
        var hints: [String] = []

        // Only add hints if we have enough data
        guard patterns.totalInteractions >= 3 else { return "" }

        // Conciseness preference
        if let prefersConcise = patterns.prefersConcise {
            if prefersConcise {
                hints.append("User prefers concise responses. Keep answers brief unless complexity requires more.")
            } else {
                hints.append("User prefers detailed responses. Provide thorough explanations.")
            }
        }

        // Accuracy emphasis
        if patterns.valuesAccuracy {
            hints.append("User has corrected responses before. Prioritize accuracy; acknowledge uncertainty rather than guessing.")
        }

        guard !hints.isEmpty else { return "" }

        return "[STYLE ADAPTATION]\n" + hints.joined(separator: "\n")
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
