import Foundation

/// User preferences for context engineering
/// These preferences are injected into prompts to improve relevance
class UserPreferences: ObservableObject {

    static let shared = UserPreferences()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let location = "userPref_location"
        static let temperatureUnit = "userPref_temperatureUnit"
        static let timeFormat = "userPref_timeFormat"
        static let distanceUnit = "userPref_distanceUnit"
        static let customContext = "userPref_customContext"
    }

    // MARK: - Temperature Unit

    enum TemperatureUnit: String, CaseIterable {
        case celsius = "Celsius"
        case fahrenheit = "Fahrenheit"
    }

    // MARK: - Time Format

    enum TimeFormat: String, CaseIterable {
        case twelve = "12-hour"
        case twentyFour = "24-hour"
    }

    // MARK: - Distance Unit

    enum DistanceUnit: String, CaseIterable {
        case metric = "Metric (km)"
        case imperial = "Imperial (miles)"
    }

    // MARK: - Published Properties

    @Published var location: String {
        didSet { defaults.set(location, forKey: Keys.location) }
    }

    @Published var temperatureUnit: TemperatureUnit {
        didSet { defaults.set(temperatureUnit.rawValue, forKey: Keys.temperatureUnit) }
    }

    @Published var timeFormat: TimeFormat {
        didSet { defaults.set(timeFormat.rawValue, forKey: Keys.timeFormat) }
    }

    @Published var distanceUnit: DistanceUnit {
        didSet { defaults.set(distanceUnit.rawValue, forKey: Keys.distanceUnit) }
    }

    @Published var customContext: String {
        didSet { defaults.set(customContext, forKey: Keys.customContext) }
    }

    // MARK: - Initialization

    private init() {
        self.location = defaults.string(forKey: Keys.location) ?? ""

        if let tempUnit = defaults.string(forKey: Keys.temperatureUnit),
           let unit = TemperatureUnit(rawValue: tempUnit) {
            self.temperatureUnit = unit
        } else {
            self.temperatureUnit = .celsius
        }

        if let timeFormat = defaults.string(forKey: Keys.timeFormat),
           let format = TimeFormat(rawValue: timeFormat) {
            self.timeFormat = format
        } else {
            self.timeFormat = .twentyFour
        }

        if let distUnit = defaults.string(forKey: Keys.distanceUnit),
           let unit = DistanceUnit(rawValue: distUnit) {
            self.distanceUnit = unit
        } else {
            self.distanceUnit = .metric
        }

        self.customContext = defaults.string(forKey: Keys.customContext) ?? ""
    }

    // MARK: - Context Generation

    /// Generate a context string to inject into prompts
    var contextString: String {
        var parts: [String] = []

        if !location.isEmpty {
            parts.append("User is located in \(location). Use this for local context (sports teams, news, etc.).")
        }

        parts.append("Use \(temperatureUnit.rawValue) for temperature.")
        parts.append("Use \(timeFormat.rawValue) format for time.")
        parts.append("Use \(distanceUnit == .metric ? "kilometers" : "miles") for distance.")

        if !customContext.isEmpty {
            parts.append(customContext)
        }

        return parts.joined(separator: " ")
    }

    /// Check if any preferences are set
    var hasPreferences: Bool {
        !location.isEmpty || !customContext.isEmpty
    }

    /// Generate search query enhancement based on preferences
    /// Converts natural language questions to search-friendly format
    func enhanceSearchQuery(_ query: String) -> String {
        var enhanced = query

        // Step 1: Remove conversational prefixes that don't help search
        enhanced = removeConversationalPrefixes(enhanced)

        // Step 2: Add location context if query seems location-relevant
        enhanced = addLocationContextIfNeeded(enhanced)

        if enhanced != query {
            print("[QueryEnhance] '\(query)' → '\(enhanced)'")
        }

        return enhanced
    }

    /// Remove prefixes that are conversational but don't help search engines
    private func removeConversationalPrefixes(_ query: String) -> String {
        let prefixes = [
            "can you tell me",
            "could you tell me",
            "please tell me",
            "i want to know",
            "i'd like to know",
            "what will be the",
            "what is the",
            "what are the",
            "what's the",
            "tell me about the",
            "tell me the",
            "show me the",
            "find me the",
            "search for the",
            "look up the"
        ]

        var result = query
        let lowerQuery = query.lowercased()

        for prefix in prefixes {
            if lowerQuery.hasPrefix(prefix) {
                result = String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        return result
    }

    /// Add location context to queries that would benefit from it
    private func addLocationContextIfNeeded(_ query: String) -> String {
        guard !location.isEmpty else { return query }

        let cityName = (location.components(separatedBy: ",").first ?? location)
            .trimmingCharacters(in: .whitespaces)
        let queryLower = query.lowercased()

        // Skip if location already mentioned
        if queryLower.contains(cityName.lowercased()) {
            return query
        }

        // Keywords that benefit from location context
        let locationKeywords = [
            // Weather & environment
            "weather", "temperature", "forecast", "rain", "snow", "humidity",
            // Local info
            "near me", "nearby", "local", "closest",
            // Sports (often have city-based teams)
            "game", "match", "score", "standings", "schedule", "team",
            // Local businesses
            "restaurant", "store", "shop", "open", "hours",
            // Events
            "events", "happening", "concert", "show"
        ]

        // Check if query would benefit from location
        if locationKeywords.contains(where: { queryLower.contains($0) }) {
            return "\(cityName) \(query)"
        }

        return query
    }
}
