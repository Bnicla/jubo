//
//  SportsCoordinator.swift
//  Jubo
//
//  Coordinates sports data fetching across multiple providers.
//  Handles provider selection, fallback logic, and result formatting.
//

import Foundation

/// Coordinates sports data fetching across multiple providers.
/// Handles provider selection, fallback, and formatting.
actor SportsCoordinator {

    // MARK: - Properties

    /// Available data providers, sorted by priority
    private var providers: [any SportsDataProvider] = []

    /// Cached results for quick re-access
    private var cache: [SportsLeague: (result: SportsResult, timestamp: Date)] = [:]

    /// Cache duration in seconds
    private let cacheDuration: TimeInterval = 60  // 1 minute

    // MARK: - Initialization

    init(providers: [any SportsDataProvider] = []) {
        self.providers = providers.sorted { $0.priority < $1.priority }
    }

    /// Register a new data provider
    func register(provider: any SportsDataProvider) {
        providers.append(provider)
        providers.sort { $0.priority < $1.priority }
    }

    // MARK: - Public API

    /// Fetch scores for a league, trying providers in priority order
    /// - Parameter league: The league to fetch scores for
    /// - Returns: SportsResult with games
    func fetchScores(for league: SportsLeague) async throws -> SportsResult {
        // Check cache first
        if let cached = cache[league],
           Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            print("[Sports] Using cached result for \(league.displayName)")
            return cached.result
        }

        // Try each provider in priority order
        var lastError: Error?

        for provider in providers {
            // Skip providers that don't support this league
            guard provider.supportsLeague(league) else {
                continue
            }

            // Skip unavailable providers
            guard await provider.isAvailable() else {
                print("[Sports] Provider \(provider.providerName) not available, skipping")
                continue
            }

            do {
                print("[Sports] Trying provider: \(provider.providerName)")
                let result = try await provider.fetchScores(for: league)

                // Cache successful result
                cache[league] = (result, Date())

                print("[Sports] Got \(result.games.count) games from \(provider.providerName)")
                return result

            } catch {
                print("[Sports] Provider \(provider.providerName) failed: \(error.localizedDescription)")
                lastError = error
                // Continue to next provider
            }
        }

        // All providers failed
        throw lastError ?? SportsError.noDataAvailable
    }

    /// Fetch scores and format for LLM
    /// - Parameters:
    ///   - league: The league to fetch
    ///   - query: The original user query
    /// - Returns: Formatted context string for LLM
    func fetchAndFormat(for league: SportsLeague, query: String) async throws -> String {
        let result = try await fetchScores(for: league)
        return SportsFormatter.formatForLLM(result: result, query: query)
    }

    /// Detect league from query and fetch scores
    /// - Parameter query: Natural language query
    /// - Returns: SportsResult with games
    func fetchScoresForQuery(_ query: String) async throws -> SportsResult {
        guard let league = SportsLeague.detect(from: query) else {
            throw SportsError.leagueNotDetected
        }
        return try await fetchScores(for: league)
    }

    /// Detect league from query, fetch, and format for LLM
    /// - Parameter query: Natural language query
    /// - Returns: Tuple of (league, formatted context)
    func fetchAndFormatForQuery(_ query: String) async throws -> (league: SportsLeague, context: String) {
        guard let league = SportsLeague.detect(from: query) else {
            throw SportsError.leagueNotDetected
        }
        let result = try await fetchScores(for: league)
        let context = SportsFormatter.formatForLLM(result: result, query: query)
        return (league, context)
    }

    /// Detect league from query
    func detectLeague(from query: String) -> SportsLeague? {
        SportsLeague.detect(from: query)
    }

    // MARK: - Cache Management

    /// Clear cached results
    func clearCache() {
        cache.removeAll()
    }

    /// Clear cache for a specific league
    func clearCache(for league: SportsLeague) {
        cache.removeValue(forKey: league)
    }
}
