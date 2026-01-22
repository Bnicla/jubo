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

    /// Pass query through - LLM has location context in system prompt
    func enhanceSearchQuery(_ query: String) -> String {
        // No preprocessing - let the search engine and LLM handle natural language
        // User's location is already in the LLM's system prompt for context
        return query
    }
}
