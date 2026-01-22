import Foundation

/// Service for fetching live sports scores from ESPN's public API
/// No API key required for basic scoreboard data
actor ESPNService {

    // MARK: - Types

    enum Sport: String, CaseIterable {
        case soccer = "soccer"
        case football = "football"
        case basketball = "basketball"
        case baseball = "baseball"
        case hockey = "hockey"
    }

    enum League: String {
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

        var sport: Sport {
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
    }

    struct GameScore {
        let homeTeam: String
        let awayTeam: String
        let homeScore: Int?
        let awayScore: Int?
        let status: String  // "Final", "In Progress", "Scheduled", etc.
        let statusDetail: String  // "Final", "2nd Half", "3:30 PM ET", etc.
        let league: String
        let date: Date?
    }

    struct SportsResult {
        let league: League
        let games: [GameScore]
        let fetchedAt: Date

        func formatForLLM(query: String) -> String {
            guard !games.isEmpty else {
                return "No \(league.displayName) games found for today."
            }

            var lines: [String] = []
            lines.append("\(league.displayName) Results:")

            for game in games {
                if let homeScore = game.homeScore, let awayScore = game.awayScore {
                    lines.append("• \(game.homeTeam) \(homeScore) - \(awayScore) \(game.awayTeam) (\(game.statusDetail))")
                } else {
                    lines.append("• \(game.homeTeam) vs \(game.awayTeam) (\(game.statusDetail))")
                }
            }

            return lines.joined(separator: "\n")
        }
    }

    // MARK: - API

    private let baseURL = "https://site.api.espn.com/apis/site/v2/sports"

    /// Fetch scoreboard for a specific league
    func fetchScores(for league: League) async throws -> SportsResult {
        let url = URL(string: "\(baseURL)/\(league.sport.rawValue)/\(league.rawValue)/scoreboard")!

        print("[ESPN] Fetching \(league.displayName) scores from: \(url)")

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ESPNError.apiError("Failed to fetch scores")
        }

        return try parseScoreboard(data: data, league: league)
    }

    /// Detect league from query and fetch scores
    func fetchScoresForQuery(_ query: String) async throws -> SportsResult {
        guard let league = detectLeague(from: query) else {
            throw ESPNError.leagueNotDetected
        }

        return try await fetchScores(for: league)
    }

    // MARK: - League Detection

    func detectLeague(from query: String) -> League? {
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
        if lower.contains("nfl") || lower.contains("football") && !lower.contains("soccer") {
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

    // MARK: - Parsing

    private func parseScoreboard(data: Data, league: League) throws -> SportsResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else {
            throw ESPNError.parseError
        }

        var games: [GameScore] = []

        for event in events {
            guard let competitions = event["competitions"] as? [[String: Any]],
                  let competition = competitions.first,
                  let competitors = competition["competitors"] as? [[String: Any]],
                  competitors.count >= 2 else {
                continue
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

            // Get status
            let status = (event["status"] as? [String: Any])?["type"] as? [String: Any]
            let statusName = status?["name"] as? String ?? "Unknown"
            let statusDetail = status?["shortDetail"] as? String ?? statusName

            // Parse date
            var gameDate: Date?
            if let dateString = event["date"] as? String {
                let formatter = ISO8601DateFormatter()
                gameDate = formatter.date(from: dateString)
            }

            if let home = homeTeam, let away = awayTeam {
                games.append(GameScore(
                    homeTeam: home,
                    awayTeam: away,
                    homeScore: homeScore,
                    awayScore: awayScore,
                    status: statusName,
                    statusDetail: statusDetail,
                    league: league.displayName,
                    date: gameDate
                ))
            }
        }

        print("[ESPN] Found \(games.count) games for \(league.displayName)")

        return SportsResult(
            league: league,
            games: games,
            fetchedAt: Date()
        )
    }
}

// MARK: - Errors

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
