import Foundation

actor SearchUsageTracker {

    // MARK: - Constants

    private let maxMonthlySearches = 2000
    private let userDefaults = UserDefaults.standard

    // MARK: - Keys

    private var currentMonthKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return "webSearchCount_\(formatter.string(from: Date()))"
    }

    private let apiKeyKey = "braveAPIKey"

    // MARK: - Search Count

    var searchesThisMonth: Int {
        userDefaults.integer(forKey: currentMonthKey)
    }

    var remainingSearches: Int {
        max(0, maxMonthlySearches - searchesThisMonth)
    }

    var hasQuotaRemaining: Bool {
        searchesThisMonth < maxMonthlySearches
    }

    func recordSearch() {
        let currentCount = searchesThisMonth
        userDefaults.set(currentCount + 1, forKey: currentMonthKey)
    }

    // MARK: - API Key Management

    var apiKey: String? {
        get { userDefaults.string(forKey: apiKeyKey) }
        set {
            if let key = newValue {
                userDefaults.set(key, forKey: apiKeyKey)
            } else {
                userDefaults.removeObject(forKey: apiKeyKey)
            }
        }
    }

    var hasAPIKey: Bool {
        guard let key = apiKey else { return false }
        return !key.isEmpty
    }

    func setAPIKey(_ key: String) {
        userDefaults.set(key, forKey: apiKeyKey)
    }

    func clearAPIKey() {
        userDefaults.removeObject(forKey: apiKeyKey)
    }

    // MARK: - Web Search Enabled

    private let webSearchEnabledKey = "webSearchEnabled"

    var isWebSearchEnabled: Bool {
        get {
            // Default to true if key hasn't been set
            if userDefaults.object(forKey: webSearchEnabledKey) == nil {
                return true
            }
            return userDefaults.bool(forKey: webSearchEnabledKey)
        }
        set {
            userDefaults.set(newValue, forKey: webSearchEnabledKey)
        }
    }

    func setWebSearchEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: webSearchEnabledKey)
    }
}
