//
//  SportsModels.swift
//  Jubo
//
//  API-agnostic domain models for sports data.
//  These models are used across all sports data providers (ESPN, web search, etc.)
//

import Foundation

// MARK: - League

/// Supported sports leagues.
/// Add new leagues here - all providers should map to these.
enum SportsLeague: String, CaseIterable, Sendable {
    // Soccer
    case championsLeague = "uefa.champions"
    case europaLeague = "uefa.europa"
    case premierLeague = "eng.1"
    case laLiga = "esp.1"
    case serieA = "ita.1"
    case bundesliga = "ger.1"
    case ligue1 = "fra.1"
    case mls = "usa.1"

    // American sports
    case nfl = "nfl"
    case nba = "nba"
    case mlb = "mlb"
    case nhl = "nhl"
    case ncaaFootball = "college-football"
    case ncaaBasketball = "mens-college-basketball"

    /// Sport category for API routing
    var sport: SportCategory {
        switch self {
        case .championsLeague, .europaLeague, .premierLeague, .laLiga,
             .serieA, .bundesliga, .ligue1, .mls:
            return .soccer
        case .nfl, .ncaaFootball:
            return .football
        case .nba, .ncaaBasketball:
            return .basketball
        case .mlb:
            return .baseball
        case .nhl:
            return .hockey
        }
    }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .championsLeague: return "UEFA Champions League"
        case .europaLeague: return "UEFA Europa League"
        case .premierLeague: return "English Premier League"
        case .laLiga: return "La Liga"
        case .serieA: return "Serie A"
        case .bundesliga: return "Bundesliga"
        case .ligue1: return "Ligue 1"
        case .mls: return "MLS"
        case .nfl: return "NFL"
        case .nba: return "NBA"
        case .mlb: return "MLB"
        case .nhl: return "NHL"
        case .ncaaFootball: return "College Football"
        case .ncaaBasketball: return "College Basketball"
        }
    }

    /// Detect league from natural language query
    static func detect(from query: String) -> SportsLeague? {
        let lower = query.lowercased()

        // Soccer leagues
        if lower.contains("champions league") || lower.contains("ucl") {
            return .championsLeague
        }
        if lower.contains("europa league") {
            return .europaLeague
        }
        if lower.contains("premier league") || lower.contains("epl") {
            return .premierLeague
        }
        if lower.contains("la liga") || lower.contains("laliga") {
            return .laLiga
        }
        if lower.contains("serie a") {
            return .serieA
        }
        if lower.contains("bundesliga") {
            return .bundesliga
        }
        if lower.contains("ligue 1") {
            return .ligue1
        }
        if lower.contains("mls") || lower.contains("major league soccer") {
            return .mls
        }

        // American sports
        if lower.contains("nfl") || (lower.contains("football") && !lower.contains("soccer")) {
            return .nfl
        }
        if lower.contains("nba") || lower.contains("basketball") {
            return .nba
        }
        if lower.contains("mlb") || lower.contains("baseball") {
            return .mlb
        }
        if lower.contains("nhl") || lower.contains("hockey") {
            return .nhl
        }
        if lower.contains("college football") || lower.contains("ncaa football") {
            return .ncaaFootball
        }
        if lower.contains("college basketball") || lower.contains("ncaa basketball") || lower.contains("march madness") {
            return .ncaaBasketball
        }

        return nil
    }
}

// MARK: - Sport Category

/// High-level sport categories for API routing
enum SportCategory: String, Sendable {
    case soccer = "soccer"
    case football = "football"
    case basketball = "basketball"
    case baseball = "baseball"
    case hockey = "hockey"
}

// MARK: - Game Status

/// Standardized game status across all providers
enum GameStatus: Sendable {
    case scheduled      // Game hasn't started
    case live           // Game in progress
    case final          // Game completed
    case postponed      // Game postponed/cancelled
    case unknown        // Unknown status

    /// Create from common status strings (handles ESPN format like "STATUS_FINAL", "STATUS_IN_PROGRESS", etc.)
    static func from(_ statusString: String, detail: String = "") -> GameStatus {
        let lower = statusString.lowercased()
        let detailLower = detail.lowercased()

        // Check for postponed/cancelled first (in detail string)
        if detailLower.contains("postponed") || detailLower.contains("canceled") || detailLower.contains("cancelled") {
            return .postponed
        }

        // Check status - use contains() to handle ESPN's "STATUS_FINAL" format
        if lower.contains("final") || lower == "post" {
            return .final
        }
        if lower.contains("in_progress") || lower == "in" || lower.contains("half") || lower.contains("quarter") || lower.contains("period") {
            return .live
        }
        if lower.contains("scheduled") || lower == "pre" {
            return .scheduled
        }

        // Check detail string as fallback
        if detailLower.contains("final") {
            return .final
        }
        if detailLower.contains("half") || detailLower.contains("quarter") || detailLower.contains("period") {
            return .live
        }

        return .unknown
    }
}

// MARK: - Sports Game

/// A single game/match result - API-agnostic
struct SportsGame: Sendable {
    let homeTeam: String
    let awayTeam: String
    let homeScore: Int?
    let awayScore: Int?
    let status: GameStatus
    let statusDetail: String    // "Final", "2nd Half", "3:30 PM ET", etc.
    let startTime: Date?
    let league: SportsLeague

    /// Whether this game has actual scores
    var hasScores: Bool {
        homeScore != nil && awayScore != nil
    }

    /// The winning team (nil if tie, no scores, or game not final)
    var winner: String? {
        guard status == .final, let home = homeScore, let away = awayScore else {
            return nil
        }
        if home > away { return homeTeam }
        if away > home { return awayTeam }
        return nil  // Tie
    }
}

// MARK: - Sports Result

/// Collection of games from a query - API-agnostic
struct SportsResult: Sendable {
    let league: SportsLeague
    let games: [SportsGame]
    let fetchedAt: Date
    let source: String          // "ESPN", "Web Search", etc.

    /// Whether this result has any data
    var isEmpty: Bool {
        games.isEmpty
    }

    /// Games grouped by status
    var finalGames: [SportsGame] {
        games.filter { $0.status == .final }
    }

    var liveGames: [SportsGame] {
        games.filter { $0.status == .live }
    }

    var scheduledGames: [SportsGame] {
        games.filter { $0.status == .scheduled }
    }

    var postponedGames: [SportsGame] {
        games.filter { $0.status == .postponed }
    }
}

// MARK: - Errors

/// Sports-related errors
enum SportsError: Error, LocalizedError {
    case leagueNotDetected
    case noDataAvailable
    case providerError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .leagueNotDetected:
            return "Could not detect which league you're asking about"
        case .noDataAvailable:
            return "No sports data available"
        case .providerError(let message):
            return "Sports data error: \(message)"
        case .parseError(let message):
            return "Failed to parse sports data: \(message)"
        }
    }
}
