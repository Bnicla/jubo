//
//  MemoryExtractor.swift
//  Jubo
//
//  Pattern-based extraction of user preferences from messages.
//  No LLM calls required - uses keyword matching and regex patterns.
//
//  Extracts:
//  - Explicit preferences ("I prefer...", "I like...", "Don't...")
//  - Identity statements ("I'm a...", "I work as...")
//  - Interests ("I follow...", "I'm interested in...")
//  - Interaction signals (requests for shorter/longer responses)
//

import Foundation

/// Extracts user preferences and facts from messages without LLM calls.
///
/// Usage:
/// ```swift
/// let extractor = MemoryExtractor()
///
/// // Extract explicit facts from user message
/// let facts = extractor.extractFacts(from: "I prefer short answers")
/// // Returns: [("User prefers short answers", .userStated)]
///
/// // Detect interaction signals
/// let signals = extractor.detectSignals(
///     userMessage: "too long, just give me the short version",
///     assistantResponse: "..."
/// )
/// // Returns: [.requestedShorter]
/// ```
struct MemoryExtractor {

    // MARK: - Extraction Patterns

    /// Patterns for explicit preference statements.
    /// Each pattern has a regex and a template for the extracted fact.
    private static let preferencePatterns: [(pattern: String, template: String)] = [
        // Direct preferences
        ("i prefer (\\w+(?:\\s+\\w+){0,3})", "User prefers $1"),
        ("i like (\\w+(?:\\s+\\w+){0,3})", "User likes $1"),
        ("i want (\\w+(?:\\s+\\w+){0,3})", "User wants $1"),
        ("i need (\\w+(?:\\s+\\w+){0,3})", "User needs $1"),

        // Negative preferences
        ("(?:i )?don'?t like (\\w+(?:\\s+\\w+){0,3})", "User dislikes $1"),
        ("(?:i )?don'?t want (\\w+(?:\\s+\\w+){0,3})", "User doesn't want $1"),
        ("(?:please )?(?:don'?t|do not|never) (\\w+(?:\\s+\\w+){0,3})", "User prefers not to have $1"),
        ("stop (\\w+ing)", "User dislikes $1"),

        // Response style
        ("(?:be|keep it) (brief|concise|short)", "User prefers concise responses"),
        ("(?:more|give me) (detail|details|information)", "User prefers detailed responses"),
        ("(?:too|that'?s) (long|verbose|wordy)", "User prefers shorter responses"),
        ("(?:too|that'?s) (short|brief)", "User prefers more detailed responses"),
    ]

    /// Patterns for identity statements.
    private static let identityPatterns: [(pattern: String, template: String)] = [
        ("i'?m a(?:n)? (\\w+(?:\\s+\\w+){0,2})", "User is a $1"),
        ("i work (?:as|in|at) (?:a(?:n)? )?(\\w+(?:\\s+\\w+){0,3})", "User works in $1"),
        ("i'?m (?:a )?(\\w+) by profession", "User is a $1"),
        ("my (?:job|profession|work) is (\\w+(?:\\s+\\w+){0,2})", "User works as $1"),
        ("i live in (\\w+(?:\\s+\\w+){0,2})", "User lives in $1"),
        ("i'?m from (\\w+(?:\\s+\\w+){0,2})", "User is from $1"),
        ("call me (\\w+)", "User's name is $1"),
        ("my name is (\\w+)", "User's name is $1"),
    ]

    /// Patterns for interests.
    private static let interestPatterns: [(pattern: String, template: String)] = [
        ("i follow (?:the )?(\\w+(?:\\s+\\w+){0,2})", "User follows $1"),
        ("i'?m a (?:fan of|supporter of) (?:the )?(\\w+(?:\\s+\\w+){0,2})", "User is a fan of $1"),
        ("i support (?:the )?(\\w+(?:\\s+\\w+){0,2})", "User supports $1"),
        ("i'?m interested in (\\w+(?:\\s+\\w+){0,3})", "User is interested in $1"),
        ("i love (\\w+(?:\\s+\\w+){0,2})", "User loves $1"),
        ("my favorite (?:is )?(\\w+(?:\\s+\\w+){0,3})", "User's favorite is $1"),
    ]

    // MARK: - Interaction Signals

    /// Signals detected from user messages indicating preferences.
    enum InteractionSignal {
        case requestedShorter       // User asked for shorter response
        case requestedLonger        // User asked for more detail
        case correctedFact          // User corrected factual error
        case correctedStyle         // User corrected response style
        case expressedFrustration   // User showed frustration
        case expressedSatisfaction  // User showed satisfaction
        case askedToRemember        // User explicitly asked to remember something
    }

    /// Patterns that indicate user wants shorter responses.
    private static let shorterSignals = [
        "too long",
        "too verbose",
        "too wordy",
        "shorter",
        "brief",
        "concise",
        "just the",
        "just tell me",
        "quick answer",
        "short version",
        "tldr",
        "tl;dr",
        "summarize",
        "in short",
    ]

    /// Patterns that indicate user wants longer responses.
    private static let longerSignals = [
        "more detail",
        "more information",
        "explain more",
        "elaborate",
        "tell me more",
        "expand on",
        "go deeper",
        "that's too short",
        "not enough",
        "can you explain",
    ]

    /// Patterns that indicate correction.
    private static let correctionSignals = [
        "that's wrong",
        "that's not right",
        "that's incorrect",
        "actually",
        "no,",
        "wrong",
        "not true",
        "that's false",
        "you're mistaken",
        "correction:",
    ]

    /// Patterns that indicate frustration.
    private static let frustrationSignals = [
        "i already said",
        "i told you",
        "why are you",
        "stop",
        "enough",
        "not what i asked",
        "didn't ask for",
    ]

    /// Patterns that indicate satisfaction.
    private static let satisfactionSignals = [
        "perfect",
        "great",
        "thanks",
        "thank you",
        "exactly",
        "that's what i needed",
        "helpful",
        "awesome",
    ]

    /// Patterns for explicit memory requests.
    private static let rememberSignals = [
        "remember that",
        "remember this",
        "keep in mind",
        "note that",
        "for future reference",
        "don't forget",
    ]

    // MARK: - Public API

    /// Extract explicit facts from a user message.
    /// Returns array of (fact content, source type) tuples.
    func extractFacts(from message: String) -> [(content: String, source: UserMemory.MemoryFact.FactSource)] {
        let lowercased = message.lowercased()
        var extracted: [(String, UserMemory.MemoryFact.FactSource)] = []

        // Try preference patterns
        for (pattern, template) in Self.preferencePatterns {
            if let fact = extractWithPattern(pattern, template: template, from: lowercased) {
                extracted.append((fact, .userStated))
            }
        }

        // Try identity patterns
        for (pattern, template) in Self.identityPatterns {
            if let fact = extractWithPattern(pattern, template: template, from: lowercased) {
                extracted.append((fact, .userStated))
            }
        }

        // Try interest patterns
        for (pattern, template) in Self.interestPatterns {
            if let fact = extractWithPattern(pattern, template: template, from: lowercased) {
                extracted.append((fact, .userStated))
            }
        }

        return extracted
    }

    /// Detect interaction signals from a user message.
    /// These signals help learn implicit preferences.
    func detectSignals(from message: String) -> [InteractionSignal] {
        let lowercased = message.lowercased()
        var signals: [InteractionSignal] = []

        // Check for shorter request
        if Self.shorterSignals.contains(where: { lowercased.contains($0) }) {
            signals.append(.requestedShorter)
        }

        // Check for longer request
        if Self.longerSignals.contains(where: { lowercased.contains($0) }) {
            signals.append(.requestedLonger)
        }

        // Check for correction
        if Self.correctionSignals.contains(where: { lowercased.contains($0) }) {
            signals.append(.correctedFact)
        }

        // Check for frustration
        if Self.frustrationSignals.contains(where: { lowercased.contains($0) }) {
            signals.append(.expressedFrustration)
        }

        // Check for satisfaction
        if Self.satisfactionSignals.contains(where: { lowercased.contains($0) }) {
            signals.append(.expressedSatisfaction)
        }

        // Check for explicit memory request
        if Self.rememberSignals.contains(where: { lowercased.contains($0) }) {
            signals.append(.askedToRemember)
        }

        return signals
    }

    /// Extract what should be remembered from an explicit "remember this" request.
    /// Returns nil if no clear memory target found.
    func extractRememberTarget(from message: String) -> String? {
        let lowercased = message.lowercased()

        // Patterns for "remember that X"
        let patterns = [
            "remember that (.+)",
            "remember:? (.+)",
            "note that (.+)",
            "keep in mind:? (.+)",
            "for future reference:? (.+)",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: lowercased) {

                let target = String(message[range])  // Use original case
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))

                if target.count > 3 && target.count < 200 {
                    return target
                }
            }
        }

        return nil
    }

    /// Analyze a user message and apply learnings to UserMemory.
    /// Call this after receiving each user message.
    @MainActor
    func processMessage(_ message: String, memory: UserMemory) {
        // Extract explicit facts
        let facts = extractFacts(from: message)
        for (content, source) in facts {
            memory.addFact(content, source: source)
        }

        // Handle explicit "remember this" requests
        if let target = extractRememberTarget(from: message) {
            memory.addFact(target, source: .userStated, confidence: 1.0)
        }

        // Detect interaction signals
        let signals = detectSignals(from: message)

        // Record interaction patterns
        var truncated = false
        var wantsMore = false
        var corrected = false
        var positive = false

        for signal in signals {
            switch signal {
            case .requestedShorter:
                truncated = true
                // Add as inferred fact if strong signal
                memory.addFact("User prefers concise responses", source: .inferred, confidence: 0.7)
            case .requestedLonger:
                wantsMore = true
                memory.addFact("User prefers detailed responses", source: .inferred, confidence: 0.7)
            case .correctedFact, .correctedStyle:
                corrected = true
            case .expressedSatisfaction:
                positive = true
            case .expressedFrustration:
                // Could add fact about what frustrated them
                break
            case .askedToRemember:
                // Handled above
                break
            }
        }

        // Record the interaction
        memory.recordInteraction(
            userMessageLength: message.count,
            responseWasTruncated: truncated,
            userAskedForMore: wantsMore,
            userCorrectedResponse: corrected,
            userGavePositiveFeedback: positive
        )
    }

    // MARK: - Private Helpers

    private func extractWithPattern(_ pattern: String, template: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1 else {
            return nil
        }

        // Get the captured group
        guard let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let captured = String(text[range])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Filter out noise words
        let noiseWords = ["a", "an", "the", "it", "that", "this", "very", "really", "just"]
        if noiseWords.contains(captured.lowercased()) || captured.count < 2 {
            return nil
        }

        // Build the fact from template
        let fact = template.replacingOccurrences(of: "$1", with: captured)

        return fact.capitalized
    }
}
