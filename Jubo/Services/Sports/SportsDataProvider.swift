//
//  SportsDataProvider.swift
//  Jubo
//
//  Protocol for sports data providers.
//  Implement this protocol to add new data sources (ESPN, web search, other APIs).
//

import Foundation

/// Protocol for sports data providers.
/// All sports data sources (ESPN, web scraping, other APIs) implement this protocol.
protocol SportsDataProvider: Sendable {

    /// Unique identifier for this provider
    var providerName: String { get }

    /// Priority order (lower = higher priority, tried first)
    var priority: Int { get }

    /// Fetch scores for a specific league
    /// - Parameter league: The league to fetch scores for
    /// - Returns: SportsResult with games
    /// - Throws: SportsError if fetch fails
    func fetchScores(for league: SportsLeague) async throws -> SportsResult

    /// Check if this provider supports a given league
    /// - Parameter league: The league to check
    /// - Returns: true if this provider can fetch data for this league
    func supportsLeague(_ league: SportsLeague) -> Bool

    /// Check if the provider is currently available (e.g., has network, API key)
    func isAvailable() async -> Bool
}

// MARK: - Default Implementations

extension SportsDataProvider {
    /// Default priority (medium)
    var priority: Int { 50 }

    /// Default: provider is always available
    func isAvailable() async -> Bool { true }

    /// Default: support all leagues
    func supportsLeague(_ league: SportsLeague) -> Bool { true }
}
