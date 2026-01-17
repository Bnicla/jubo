//
//  WebSearchCoordinator.swift
//  Jubo
//
//  Orchestrates external data fetching for LLM context augmentation.
//  Routes queries to appropriate services (WeatherKit, Brave Search, etc.)
//  and formats results for injection into LLM prompts.
//

import Foundation

/// Coordinates external data fetching for LLM context augmentation.
///
/// This coordinator handles the complete flow:
/// 1. Intent detection - determine if external data is needed
/// 2. Query type classification - route to specialized service (weather, sports, general)
/// 3. User confirmation - get permission before making external requests
/// 4. Data fetching - call appropriate API (WeatherKit, Brave Search)
/// 5. Context formatting - prepare data for LLM prompt injection
///
/// Usage:
/// ```swift
/// let coordinator = WebSearchCoordinator(llmService: llmService)
/// if await coordinator.checkIfSearchNeeded(for: query) {
///     // Show confirmation UI, then:
///     let result = await coordinator.performConfirmedSearch(for: query)
/// }
/// ```
@MainActor
class WebSearchCoordinator: ObservableObject {

    // MARK: - Search State

    /// Current state of the search/fetch operation.
    /// Published for UI binding to show appropriate indicators.
    enum SearchState: Equatable {
        case idle
        case detectingIntent
        case awaitingConfirmation(query: String, isWeather: Bool)
        case sanitizing
        case searching(query: String)
        case fetchingWeather(location: String)
        case complete(resultCount: Int)
        case weatherComplete
        case failed(reason: String)
        case skipped(reason: String)
    }

    // MARK: - Search Result

    /// Result of a search/fetch attempt, containing formatted context for LLM.
    struct SearchAttemptResult {
        /// Original user query
        let originalQuery: String
        /// Sanitized/enhanced query used for search
        let sanitizedQuery: String?
        /// Raw search results (nil for weather queries)
        let searchResults: [BraveSearchService.SearchResult]?
        /// Formatted context string ready for LLM prompt injection
        let formattedContext: String?
        /// Source URLs/attributions for the data
        let sources: [String]?
        /// Error if the operation failed
        let error: WebSearchError?
        /// Expected detail level for LLM response
        let detailLevel: ResponseDetailLevel

        /// Whether the operation succeeded and produced usable context
        var succeeded: Bool {
            formattedContext != nil && error == nil
        }
    }

    // MARK: - Published Properties

    @Published var state: SearchState = .idle

    // MARK: - Dependencies

    private let searchService = BraveSearchService()
    private let weatherService = WeatherKitService()
    private let usageTracker = SearchUsageTracker()
    private weak var llmService: LLMService?

    /// Expected response detail level (set during intent detection)
    private(set) var expectedDetailLevel: ResponseDetailLevel = .detailed

    /// Detected query type (weather, sports, general)
    private(set) var detectedQueryType: QueryType = .general

    // MARK: - Initialization

    init(llmService: LLMService? = nil) {
        self.llmService = llmService
    }

    // MARK: - Public API

    /// Check if web search is enabled and configured
    func checkIsEnabled() async -> Bool {
        let enabled = await usageTracker.isWebSearchEnabled
        let hasKey = await usageTracker.hasAPIKey
        return enabled && hasKey
    }

    /// Check if there's quota remaining
    var hasQuota: Bool {
        get async {
            await usageTracker.hasQuotaRemaining
        }
    }

    /// Get remaining search count
    var remainingSearches: Int {
        get async {
            await usageTracker.remainingSearches
        }
    }

    /// Get current month's search count
    var searchesThisMonth: Int {
        get async {
            await usageTracker.searchesThisMonth
        }
    }

    /// Check if a query needs web search and request user confirmation
    /// Returns true if confirmation is needed (state will be .awaitingConfirmation)
    func checkIfSearchNeeded(for query: String) async -> Bool {
        state = .detectingIntent
        print("[WebSearch] Checking query: \(query)")

        // First, classify query type (weather, sports, general)
        detectedQueryType = IntentDetector.classifyQueryType(query)
        print("[WebSearch] Query type: \(detectedQueryType)")

        // Weather queries can be handled directly with WeatherKit (no API key needed)
        if detectedQueryType == .weather {
            // Extract or infer location for weather
            var location = IntentDetector.extractWeatherLocation(from: query)
            if location == nil || location!.isEmpty {
                // Use user's configured location as fallback
                let userLocation = UserPreferences.shared.location
                if !userLocation.isEmpty {
                    location = userLocation.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
                    print("[Weather] Using user preference location: \(location ?? "nil")")
                }
            }

            if let loc = location, !loc.isEmpty {
                print("[Weather] CONFIRM: Requesting confirmation for weather in '\(loc)'")
                state = .awaitingConfirmation(query: loc, isWeather: true)
                return true
            } else {
                print("[Weather] SKIP: No location found in query or preferences")
                // Fall through to web search
            }
        }

        // For non-weather queries, check if web search is enabled
        guard await usageTracker.isWebSearchEnabled else {
            print("[WebSearch] SKIP: Web search disabled")
            state = .idle
            return false
        }

        // Check API key
        guard let apiKey = await usageTracker.apiKey, !apiKey.isEmpty else {
            print("[WebSearch] SKIP: No API key")
            state = .idle
            return false
        }
        print("[WebSearch] API key found")

        // Check quota
        guard await usageTracker.hasQuotaRemaining else {
            print("[WebSearch] SKIP: No quota remaining")
            state = .idle
            return false
        }

        // Use LLM to detect if query needs web search
        guard let llm = llmService else {
            print("[WebSearch] SKIP: No LLM service available")
            state = .idle
            return false
        }

        let needsSearch = await llm.needsWebSearch(query: query)
        guard needsSearch else {
            print("[WebSearch] SKIP: LLM determined no search needed")
            state = .idle
            return false
        }

        // Classify expected response detail level (brief vs detailed)
        let llmDetail = await llm.classifyResponseDetail(query: query)
        expectedDetailLevel = llmDetail == .brief ? .brief : .detailed
        print("[WebSearch] Expected response detail: \(expectedDetailLevel == .brief ? "BRIEF" : "DETAILED")")

        // Check if query can be sanitized (still use this for PII protection)
        let sanitized = QuerySanitizer.sanitize(query: query)
        print("[WebSearch] Sanitized: shouldProceed=\(sanitized.shouldProceed), containedPII=\(sanitized.containedPII)")
        guard sanitized.shouldProceed else {
            print("[WebSearch] SKIP: Sanitization failed (PII detected)")
            state = .idle
            return false
        }

        // Enhance query with user preferences (e.g., "spurs" → "San Antonio Spurs")
        let enhancedQuery = UserPreferences.shared.enhanceSearchQuery(sanitized.sanitizedQuery)
        print("[WebSearch] Enhanced query: '\(enhancedQuery)'")

        // Search is possible - request confirmation
        print("[WebSearch] CONFIRM: Requesting confirmation for '\(enhancedQuery)'")
        state = .awaitingConfirmation(query: enhancedQuery, isWeather: false)
        return true
    }

    /// Perform the confirmed search/fetch operation.
    ///
    /// Routes to the appropriate service based on `detectedQueryType`:
    /// - `.weather` → WeatherKit (no API quota used)
    /// - `.sports` → Sports API (future)
    /// - `.general` → Brave Search API
    ///
    /// - Parameter query: The original user query
    /// - Returns: SearchAttemptResult with formatted context or error
    func performConfirmedSearch(for query: String) async -> SearchAttemptResult {
        // Route weather queries to WeatherKit
        if detectedQueryType == .weather {
            return await performWeatherFetch(for: query)
        }

        // Otherwise, perform web search
        return await performWebSearch(for: query)
    }

    /// Fetch weather data using Apple's WeatherKit.
    ///
    /// This method:
    /// 1. Extracts location from query or falls back to user preferences
    /// 2. Geocodes location string to coordinates
    /// 3. Fetches weather from WeatherKit
    /// 4. Formats data for LLM context injection
    ///
    /// - Parameter query: The weather-related query
    /// - Returns: SearchAttemptResult with weather context or error
    private func performWeatherFetch(for query: String) async -> SearchAttemptResult {
        // Extract location from query or use user preference
        var location = IntentDetector.extractWeatherLocation(from: query)
        if location == nil || location!.isEmpty {
            let userLocation = UserPreferences.shared.location
            if !userLocation.isEmpty {
                location = userLocation.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
            }
        }

        guard let loc = location, !loc.isEmpty else {
            state = .failed(reason: "No location specified")
            return SearchAttemptResult(
                originalQuery: query,
                sanitizedQuery: nil,
                searchResults: nil,
                formattedContext: nil,
                sources: nil,
                error: .apiError("Could not determine location for weather"),
                detailLevel: expectedDetailLevel
            )
        }

        state = .fetchingWeather(location: loc)
        print("[Weather] Fetching weather for: \(loc)")

        // Get temperature preference from main actor context before calling into actor
        let useCelsius = UserPreferences.shared.temperatureUnit == .celsius

        do {
            let weatherData = try await weatherService.fetchWeather(for: loc, useCelsius: useCelsius)
            let context = weatherData.formatForLLM(query: query)

            state = .weatherComplete
            print("[Weather] Context ready: \(context.count) chars")

            return SearchAttemptResult(
                originalQuery: query,
                sanitizedQuery: loc,
                searchResults: nil,  // No web search results for weather
                formattedContext: context,
                sources: ["Apple Weather"],
                error: nil,
                detailLevel: expectedDetailLevel
            )

        } catch {
            print("[Weather] Error: \(error.localizedDescription)")
            state = .failed(reason: error.localizedDescription)
            return SearchAttemptResult(
                originalQuery: query,
                sanitizedQuery: loc,
                searchResults: nil,
                formattedContext: nil,
                sources: nil,
                error: .apiError(error.localizedDescription),
                detailLevel: expectedDetailLevel
            )
        }
    }

    /// Perform web search using Brave Search API.
    ///
    /// This method:
    /// 1. Validates API key availability
    /// 2. Sanitizes query (removes PII)
    /// 3. Enhances query with user preferences (location context)
    /// 4. Calls Brave Search API
    /// 5. Formats results for LLM context injection
    ///
    /// - Parameter query: The search query
    /// - Returns: SearchAttemptResult with search context or error
    private func performWebSearch(for query: String) async -> SearchAttemptResult {
        state = .sanitizing

        // Get API key
        guard let apiKey = await usageTracker.apiKey, !apiKey.isEmpty else {
            state = .failed(reason: "API key not set")
            return SearchAttemptResult(
                originalQuery: query,
                sanitizedQuery: nil,
                searchResults: nil,
                formattedContext: nil,
                sources: nil,
                error: .apiKeyMissing,
                detailLevel: expectedDetailLevel
            )
        }

        // Sanitize query
        let sanitized = QuerySanitizer.sanitize(query: query)

        guard sanitized.shouldProceed else {
            let reason = sanitized.containedPII ? "Contains personal info" : "Query too short"
            state = .skipped(reason: reason)
            return SearchAttemptResult(
                originalQuery: query,
                sanitizedQuery: sanitized.sanitizedQuery,
                searchResults: nil,
                formattedContext: nil,
                sources: nil,
                error: .sensitiveContent,
                detailLevel: expectedDetailLevel
            )
        }

        // Extract and enhance search query for better results
        let extractedQuery = IntentDetector.extractSearchQuery(from: sanitized.sanitizedQuery)
        let searchQuery = UserPreferences.shared.enhanceSearchQuery(extractedQuery)
        print("[WebSearch] Search query: '\(extractedQuery)' → '\(searchQuery)'")

        // Perform search
        state = .searching(query: searchQuery)

        do {
            let results = try await searchService.search(query: searchQuery, apiKey: apiKey)

            // Record usage
            await usageTracker.recordSearch()

            // Determine how many results to use based on detail level
            let maxResults = expectedDetailLevel == .detailed ? 2 : 1
            let maxSources = expectedDetailLevel == .detailed ? 2 : 1

            // Format results for LLM with appropriate detail level
            let context = SearchContextFormatter.formatForLLM(
                originalQuery: query,
                results: results,
                detailLevel: expectedDetailLevel,
                maxResults: maxResults
            )

            let sources = SearchContextFormatter.extractSources(from: results, maxSources: maxSources)

            state = .complete(resultCount: min(results.count, maxResults))
            print("[WebSearch] Context ready: \(context.count) chars")

            return SearchAttemptResult(
                originalQuery: query,
                sanitizedQuery: searchQuery,
                searchResults: Array(results.prefix(maxResults)),
                formattedContext: context,
                sources: sources,
                error: nil,
                detailLevel: expectedDetailLevel
            )

        } catch let error as WebSearchError {
            state = .failed(reason: error.localizedDescription)
            return SearchAttemptResult(
                originalQuery: query,
                sanitizedQuery: searchQuery,
                searchResults: nil,
                formattedContext: nil,
                sources: nil,
                error: error,
                detailLevel: expectedDetailLevel
            )

        } catch {
            state = .failed(reason: "Search failed")
            return SearchAttemptResult(
                originalQuery: query,
                sanitizedQuery: searchQuery,
                searchResults: nil,
                formattedContext: nil,
                sources: nil,
                error: .apiError(error.localizedDescription),
                detailLevel: expectedDetailLevel
            )
        }
    }

    /// User declined search - proceed with offline response
    func declineSearch() {
        state = .skipped(reason: "Using offline mode")
    }

    /// Reset state to idle
    func reset() {
        state = .idle
    }

    // MARK: - Settings Access

    func setAPIKey(_ key: String) async {
        await usageTracker.setAPIKey(key)
    }

    func clearAPIKey() async {
        await usageTracker.clearAPIKey()
    }

    func setWebSearchEnabled(_ enabled: Bool) async {
        await usageTracker.setWebSearchEnabled(enabled)
    }

    func getAPIKey() async -> String? {
        await usageTracker.apiKey
    }

    func isWebSearchEnabled() async -> Bool {
        await usageTracker.isWebSearchEnabled
    }
}
