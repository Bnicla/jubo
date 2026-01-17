//
//  UserMemory.swift
//  Jubo
//
//  On-device memory storage for learned user preferences and interaction patterns.
//  All data stays local - never synced to cloud.
//
//  Memory Types:
//  - Semantic: Facts about the user ("prefers concise answers", "works in tech")
//  - Patterns: Observed interaction behaviors (message length, correction frequency)
//

import Foundation

/// Manages on-device memory of user preferences and interaction patterns.
/// Singleton accessed via `UserMemory.shared`.
///
/// Usage:
/// ```swift
/// // Store a learned fact
/// UserMemory.shared.addFact("User prefers concise answers", source: .inferred)
///
/// // Record an interaction for pattern learning
/// UserMemory.shared.recordInteraction(
///     userMessageLength: 45,
///     responseWasTruncated: false,
///     userCorrectedResponse: false
/// )
///
/// // Get relevant memories for prompt injection
/// let memories = UserMemory.shared.relevantFacts(limit: 5)
/// ```
@MainActor
class UserMemory: ObservableObject {

    static let shared = UserMemory()

    // MARK: - Storage Keys

    private enum Keys {
        static let facts = "userMemory_facts"
        static let patterns = "userMemory_patterns"
        static let version = "userMemory_version"
    }

    private let currentVersion = 1
    private let defaults = UserDefaults.standard

    // MARK: - Memory Types

    /// A single fact learned about the user.
    struct MemoryFact: Codable, Identifiable, Equatable {
        let id: UUID
        let content: String
        let source: FactSource
        let confidence: Double  // 0.0 - 1.0
        let createdAt: Date
        var lastRelevantAt: Date  // Updated when fact is used in prompt

        enum FactSource: String, Codable {
            case userStated     // User explicitly said this ("I prefer...")
            case inferred       // Derived from interaction patterns
            case corrected      // User corrected a behavior
        }

        init(content: String, source: FactSource, confidence: Double = 0.8) {
            self.id = UUID()
            self.content = content
            self.source = source
            self.confidence = confidence
            self.createdAt = Date()
            self.lastRelevantAt = Date()
        }
    }

    /// Observed patterns from user interactions.
    struct InteractionPatterns: Codable {
        var totalInteractions: Int = 0
        var totalUserCharacters: Int = 0
        var truncationRequests: Int = 0      // Times user asked for shorter response
        var expansionRequests: Int = 0       // Times user asked for more detail
        var correctionsCount: Int = 0        // Times user corrected a response
        var positiveFeedbackCount: Int = 0   // Explicit positive feedback

        // Derived preferences (computed from patterns)

        /// Average length of user messages
        var avgUserMessageLength: Double {
            guard totalInteractions > 0 else { return 0 }
            return Double(totalUserCharacters) / Double(totalInteractions)
        }

        /// Whether user seems to prefer concise responses
        /// Returns nil if not enough data to determine
        var prefersConcise: Bool? {
            let total = truncationRequests + expansionRequests
            guard total >= 2 else { return nil }  // Need at least 2 signals

            if truncationRequests > expansionRequests * 2 {
                return true
            } else if expansionRequests > truncationRequests * 2 {
                return false
            }
            return nil  // Mixed signals
        }

        /// Whether user frequently corrects responses (values accuracy highly)
        var valuesAccuracy: Bool {
            guard totalInteractions >= 5 else { return false }
            let correctionRate = Double(correctionsCount) / Double(totalInteractions)
            return correctionRate > 0.15  // More than 15% correction rate
        }
    }

    // MARK: - Published Properties

    @Published private(set) var facts: [MemoryFact] = []
    @Published private(set) var patterns: InteractionPatterns = InteractionPatterns()

    // MARK: - Initialization

    private init() {
        loadFromStorage()
    }

    // MARK: - Fact Management

    /// Add a new fact about the user.
    /// Deduplicates similar facts automatically.
    func addFact(_ content: String, source: MemoryFact.FactSource, confidence: Double = 0.8) {
        // Check for duplicates (case-insensitive, fuzzy)
        let normalized = content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if facts.contains(where: { $0.content.lowercased().contains(normalized) ||
                                   normalized.contains($0.content.lowercased()) }) {
            print("[Memory] Skipping duplicate fact: \(content)")
            return
        }

        // Limit total facts to prevent prompt bloat
        if facts.count >= 20 {
            // Remove oldest, lowest-confidence fact
            if let removeIndex = facts
                .enumerated()
                .min(by: { ($0.element.confidence, $0.element.lastRelevantAt) <
                          ($1.element.confidence, $1.element.lastRelevantAt) })?
                .offset {
                facts.remove(at: removeIndex)
            }
        }

        let fact = MemoryFact(content: content, source: source, confidence: confidence)
        facts.append(fact)
        saveToStorage()
        print("[Memory] Added fact: \(content) (source: \(source.rawValue))")
    }

    /// Remove a specific fact.
    func removeFact(id: UUID) {
        facts.removeAll { $0.id == id }
        saveToStorage()
    }

    /// Clear all learned facts (user-triggered reset).
    func clearAllFacts() {
        facts.removeAll()
        saveToStorage()
        print("[Memory] Cleared all facts")
    }

    /// Get relevant facts for prompt injection.
    /// Prioritizes high-confidence, recently-relevant facts.
    func relevantFacts(limit: Int = 5) -> [MemoryFact] {
        let sorted = facts.sorted { lhs, rhs in
            // Sort by: confidence (desc), then lastRelevantAt (desc)
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            return lhs.lastRelevantAt > rhs.lastRelevantAt
        }

        let selected = Array(sorted.prefix(limit))

        // Update lastRelevantAt for selected facts
        for fact in selected {
            if let index = facts.firstIndex(where: { $0.id == fact.id }) {
                facts[index].lastRelevantAt = Date()
            }
        }

        if !selected.isEmpty {
            saveToStorage()
        }

        return selected
    }

    // MARK: - Interaction Pattern Tracking

    /// Record an interaction for pattern learning.
    /// Call this after each assistant response.
    func recordInteraction(
        userMessageLength: Int,
        responseWasTruncated: Bool = false,
        userAskedForMore: Bool = false,
        userCorrectedResponse: Bool = false,
        userGavePositiveFeedback: Bool = false
    ) {
        patterns.totalInteractions += 1
        patterns.totalUserCharacters += userMessageLength

        if responseWasTruncated {
            patterns.truncationRequests += 1
        }
        if userAskedForMore {
            patterns.expansionRequests += 1
        }
        if userCorrectedResponse {
            patterns.correctionsCount += 1
        }
        if userGavePositiveFeedback {
            patterns.positiveFeedbackCount += 1
        }

        saveToStorage()
    }

    /// Reset interaction patterns (but keep facts).
    func resetPatterns() {
        patterns = InteractionPatterns()
        saveToStorage()
        print("[Memory] Reset interaction patterns")
    }

    /// Full reset - clear everything.
    func resetAll() {
        facts.removeAll()
        patterns = InteractionPatterns()
        saveToStorage()
        print("[Memory] Full memory reset")
    }

    // MARK: - Persistence

    private func loadFromStorage() {
        // Check version for future migrations
        let storedVersion = defaults.integer(forKey: Keys.version)
        if storedVersion != currentVersion && storedVersion != 0 {
            migrateIfNeeded(from: storedVersion)
        }

        // Load facts
        if let factsData = defaults.data(forKey: Keys.facts),
           let decoded = try? JSONDecoder().decode([MemoryFact].self, from: factsData) {
            self.facts = decoded
            print("[Memory] Loaded \(facts.count) facts")
        }

        // Load patterns
        if let patternsData = defaults.data(forKey: Keys.patterns),
           let decoded = try? JSONDecoder().decode(InteractionPatterns.self, from: patternsData) {
            self.patterns = decoded
            print("[Memory] Loaded patterns: \(patterns.totalInteractions) interactions")
        }
    }

    private func saveToStorage() {
        defaults.set(currentVersion, forKey: Keys.version)

        if let factsData = try? JSONEncoder().encode(facts) {
            defaults.set(factsData, forKey: Keys.facts)
        }

        if let patternsData = try? JSONEncoder().encode(patterns) {
            defaults.set(patternsData, forKey: Keys.patterns)
        }
    }

    private func migrateIfNeeded(from oldVersion: Int) {
        // Future migration logic here
        print("[Memory] Migrating from version \(oldVersion) to \(currentVersion)")
    }

    // MARK: - Debug

    /// Debug description of current memory state.
    var debugDescription: String {
        var lines: [String] = ["[UserMemory State]"]
        lines.append("Facts (\(facts.count)):")
        for fact in facts {
            lines.append("  • \(fact.content) [\(fact.source.rawValue), conf: \(fact.confidence)]")
        }
        lines.append("Patterns:")
        lines.append("  • Interactions: \(patterns.totalInteractions)")
        lines.append("  • Avg message length: \(Int(patterns.avgUserMessageLength))")
        lines.append("  • Prefers concise: \(patterns.prefersConcise.map { $0 ? "yes" : "no" } ?? "unknown")")
        lines.append("  • Values accuracy: \(patterns.valuesAccuracy ? "yes" : "no")")
        return lines.joined(separator: "\n")
    }
}
