import Foundation

@MainActor
class WebSearchCoordinator: ObservableObject {

    // MARK: - Search State

    enum SearchState: Equatable {
        case idle
        case detectingIntent
        case sanitizing
        case searching(query: String)
        case complete(resultCount: Int)
        case failed(reason: String)
        case skipped(reason: String)
    }

    // MARK: - Search Result

    struct SearchAttemptResult {
        let originalQuery: String
        let sanitizedQuery: String?
        let searchResults: [BraveSearchService.SearchResult]?
        let formattedContext: String?
        let sources: [String]?
        let error: WebSearchError?

        var succeeded: Bool {
            formattedContext != nil && error == nil
        }
    }

    // MARK: - Published Properties

    @Published var state: SearchState = .idle

    // MARK: - Dependencies

    private let searchService = BraveSearchService()
    private let usageTracker = SearchUsageTracker()

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

    /// Attempt a web search for the given query
    /// Returns search results and formatted context, or falls back gracefully on error
    func attemptSearch(for query: String) async -> SearchAttemptResult {
        state = .detectingIntent

        // Check if web search is enabled
        guard await usageTracker.isWebSearchEnabled else {
            state = .skipped(reason: "Web search disabled")
            return SearchAttemptResult(
                originalQuery: query,
                sanitizedQuery: nil,
                searchResults: nil,
                formattedContext: nil,
                sources: nil,
                error: nil
            )
        }

        // Check API key
        guard let apiKey = await usageTracker.apiKey, !apiKey.isEmpty else {
            state = .skipped(reason: "API key not set")
            return SearchAttemptResult(
                originalQuery: query,
                sanitizedQuery: nil,
                searchResults: nil,
                formattedContext: nil,
                sources: nil,
                error: .apiKeyMissing
            )
        }

        // Check quota
        guard await usageTracker.hasQuotaRemaining else {
            state = .failed(reason: "Monthly limit reached")
            return SearchAttemptResult(
                originalQuery: query,
                sanitizedQuery: nil,
                searchResults: nil,
                formattedContext: nil,
                sources: nil,
                error: .quotaExceeded
            )
        }

        // Detect intent
        let intent = IntentDetector.detectIntent(query: query)
        guard intent != .noSearchNeeded else {
            state = .idle
            return SearchAttemptResult(
                originalQuery: query,
                sanitizedQuery: nil,
                searchResults: nil,
                formattedContext: nil,
                sources: nil,
                error: nil
            )
        }

        // Sanitize query
        state = .sanitizing
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
                error: .sensitiveContent
            )
        }

        // Extract search query (remove conversational prefixes)
        let searchQuery = IntentDetector.extractSearchQuery(from: sanitized.sanitizedQuery)

        // Perform search
        state = .searching(query: searchQuery)

        do {
            let results = try await searchService.search(query: searchQuery, apiKey: apiKey)

            // Record usage
            await usageTracker.recordSearch()

            // Format results for LLM
            let context = SearchContextFormatter.formatForLLM(
                originalQuery: query,
                results: results
            )

            let sources = SearchContextFormatter.extractSources(from: results)

            state = .complete(resultCount: results.count)

            return SearchAttemptResult(
                originalQuery: query,
                sanitizedQuery: searchQuery,
                searchResults: results,
                formattedContext: context,
                sources: sources,
                error: nil
            )

        } catch let error as WebSearchError {
            state = .failed(reason: error.localizedDescription)
            return SearchAttemptResult(
                originalQuery: query,
                sanitizedQuery: searchQuery,
                searchResults: nil,
                formattedContext: nil,
                sources: nil,
                error: error
            )

        } catch {
            state = .failed(reason: "Search failed")
            return SearchAttemptResult(
                originalQuery: query,
                sanitizedQuery: searchQuery,
                searchResults: nil,
                formattedContext: nil,
                sources: nil,
                error: .apiError(error.localizedDescription)
            )
        }
    }

    /// Quick check if a query should trigger web search (without actually searching)
    func shouldSearch(query: String) -> Bool {
        let intent = IntentDetector.detectIntent(query: query)
        return intent != .noSearchNeeded
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
