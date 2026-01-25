//
//  ESPNService.swift
//  Jubo
//
//  ESPN data provider for sports scores.
//  Uses ESPN's free public API - no API key required.
//
//  Supported leagues:
//  - Soccer: Champions League, Europa League, Premier League, La Liga, etc.
//  - American: NFL, NBA, MLB, NHL, College Football/Basketball
//

import Foundation

/// ESPN implementation of SportsDataProvider.
/// Fetches live sports scores from ESPN's public API.
actor ESPNService: SportsDataProvider {

    // MARK: - SportsDataProvider

    nonisolated var providerName: String { "ESPN" }
    nonisolated var priority: Int { 10 }  // High priority - try ESPN first

    func fetchScores(for league: SportsLeague) async throws -> SportsResult {
        let url = buildURL(for: league)

        print("[ESPN] Fetching \(league.displayName) scores from: \(url)")

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SportsError.providerError("ESPN API returned non-200 status")
        }

        return try parseScoreboard(data: data, league: league)
    }

    nonisolated func supportsLeague(_ league: SportsLeague) -> Bool {
        // ESPN supports all our defined leagues
        true
    }

    func isAvailable() async -> Bool {
        // ESPN is always available (no API key required)
        // Could add network reachability check here
        true
    }

    // MARK: - URL Building

    private let baseURL = "https://site.api.espn.com/apis/site/v2/sports"

    private func buildURL(for league: SportsLeague) -> URL {
        URL(string: "\(baseURL)/\(league.sport.rawValue)/\(league.rawValue)/scoreboard")!
    }

    // MARK: - Parsing

    private func parseScoreboard(data: Data, league: SportsLeague) throws -> SportsResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else {
            throw SportsError.parseError("Invalid ESPN response format")
        }

        var games: [SportsGame] = []

        for event in events {
            if let game = parseEvent(event, league: league) {
                games.append(game)
            }
        }

        print("[ESPN] Found \(games.count) games for \(league.displayName)")

        return SportsResult(
            league: league,
            games: games,
            fetchedAt: Date(),
            source: providerName
        )
    }

    private func parseEvent(_ event: [String: Any], league: SportsLeague) -> SportsGame? {
        guard let competitions = event["competitions"] as? [[String: Any]],
              let competition = competitions.first,
              let competitors = competition["competitors"] as? [[String: Any]],
              competitors.count >= 2 else {
            return nil
        }

        // Find home and away teams
        var homeTeam: String?
        var awayTeam: String?
        var homeScore: Int?
        var awayScore: Int?

        for competitor in competitors {
            guard let team = competitor["team"] as? [String: Any],
                  let teamName = team["shortDisplayName"] as? String ?? team["displayName"] as? String else {
                continue
            }

            let isHome = (competitor["homeAway"] as? String) == "home"
            let score = Int(competitor["score"] as? String ?? "")

            if isHome {
                homeTeam = teamName
                homeScore = score
            } else {
                awayTeam = teamName
                awayScore = score
            }
        }

        // Get status - ESPN uses "type" object with "name" (e.g., "STATUS_FINAL") and "state" (e.g., "post")
        let statusDict = (event["status"] as? [String: Any])?["type"] as? [String: Any]
        let statusName = statusDict?["name"] as? String ?? "Unknown"
        let statusState = statusDict?["state"] as? String ?? ""  // "pre", "in", "post"
        let statusDetail = statusDict?["shortDetail"] as? String ?? statusName

        // Use state if available (more reliable than name)
        let effectiveStatus = statusState.isEmpty ? statusName : statusState
        print("[ESPN] Game: \(awayTeam ?? "?") \(awayScore ?? -1) @ \(homeTeam ?? "?") \(homeScore ?? -1) - status: \(effectiveStatus), detail: \(statusDetail)")

        // Parse date
        var gameDate: Date?
        if let dateString = event["date"] as? String {
            let formatter = ISO8601DateFormatter()
            gameDate = formatter.date(from: dateString)
        }

        guard let home = homeTeam, let away = awayTeam else {
            return nil
        }

        // Convert ESPN status to our domain status
        // Use state ("pre", "in", "post") which is more reliable than name ("STATUS_FINAL")
        let status = GameStatus.from(effectiveStatus, detail: statusDetail)

        return SportsGame(
            homeTeam: home,
            awayTeam: away,
            homeScore: homeScore,
            awayScore: awayScore,
            status: status,
            statusDetail: statusDetail,
            startTime: gameDate,
            league: league
        )
    }
}

// MARK: - Legacy API (for backward compatibility during transition)

extension ESPNService {

    /// Legacy method - detect league from query
    func detectLeague(from query: String) -> SportsLeague? {
        SportsLeague.detect(from: query)
    }

    /// Legacy method - fetch with query
    func fetchScoresForQuery(_ query: String) async throws -> SportsResult {
        guard let league = detectLeague(from: query) else {
            throw SportsError.leagueNotDetected
        }
        return try await fetchScores(for: league)
    }
}

// MARK: - ESPN-specific Errors (kept for specific error handling)

enum ESPNError: Error, LocalizedError {
    case apiError(String)
    case parseError
    case leagueNotDetected

    var errorDescription: String? {
        switch self {
        case .apiError(let message): return "ESPN API error: \(message)"
        case .parseError: return "Failed to parse ESPN response"
        case .leagueNotDetected: return "Could not detect which league you're asking about"
        }
    }
}
