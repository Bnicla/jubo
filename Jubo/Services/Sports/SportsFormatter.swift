//
//  SportsFormatter.swift
//  Jubo
//
//  Formats sports data for LLM context injection.
//  This is the single source of truth for how sports results are presented to the model.
//  All data providers output SportsResult, which gets formatted here.
//

import Foundation

/// Formats sports results for LLM context injection.
/// Centralizes all formatting logic so it's consistent regardless of data source.
struct SportsFormatter {

    // MARK: - Main Formatting

    /// Format sports results for LLM context injection.
    /// - Parameters:
    ///   - result: The sports result to format
    ///   - query: The original user query
    /// - Returns: Formatted context string for the LLM
    static func formatForLLM(result: SportsResult, query: String) -> String {
        guard !result.isEmpty else {
            return """
                [DO NOT USE TOOLS - DATA BELOW]

                No \(result.league.displayName) games found.

                Question: \(query)
                """
        }

        var lines: [String] = []
        lines.append("[DO NOT USE TOOLS - DATA BELOW]")
        lines.append("")
        lines.append("\(result.league.displayName) Scores:")

        // Format each game based on its status
        for game in result.games {
            lines.append(formatGame(game))
        }

        lines.append("")
        lines.append("Copy these results exactly as shown above, including all numbers. Question: \(query)")

        return lines.joined(separator: "\n")
    }

    /// Format a list of games from multiple results (e.g., combined sources)
    static func formatGamesForLLM(games: [SportsGame], leagueName: String, query: String) -> String {
        guard !games.isEmpty else {
            return """
                [DO NOT USE TOOLS - DATA BELOW]

                No \(leagueName) games found.

                Question: \(query)
                """
        }

        var lines: [String] = []
        lines.append("[DO NOT USE TOOLS - DATA BELOW]")
        lines.append("")
        lines.append("\(leagueName) Scores:")

        for game in games {
            lines.append(formatGame(game))
        }

        lines.append("")
        lines.append("List ONLY these scores. Do not add extra text. Question: \(query)")

        return lines.joined(separator: "\n")
    }

    // MARK: - Game Formatting

    /// Format a single game based on its status
    /// Uses explicit "SCORE:" prefix to prevent model from stripping scores
    private static func formatGame(_ game: SportsGame) -> String {
        switch game.status {
        case .postponed:
            return "• \(game.awayTeam) vs \(game.homeTeam) — POSTPONED"

        case .final:
            let away = game.awayScore ?? 0
            let home = game.homeScore ?? 0
            return "• \(game.awayTeam) \(away) - \(home) \(game.homeTeam) (FINAL)"

        case .live:
            let away = game.awayScore ?? 0
            let home = game.homeScore ?? 0
            return "• \(game.awayTeam) \(away) - \(home) \(game.homeTeam) (\(game.statusDetail))"

        case .scheduled:
            return "• \(game.awayTeam) vs \(game.homeTeam) — \(game.statusDetail)"

        case .unknown:
            let away = game.awayScore ?? 0
            let home = game.homeScore ?? 0
            if game.hasScores {
                return "• \(game.awayTeam) \(away) - \(home) \(game.homeTeam)"
            } else {
                return "• \(game.awayTeam) vs \(game.homeTeam) — \(game.statusDetail)"
            }
        }
    }

    // MARK: - Alternative Formats

    /// Format with grouped sections (Final, Live, Upcoming)
    static func formatGroupedForLLM(result: SportsResult, query: String) -> String {
        guard !result.isEmpty else {
            return formatForLLM(result: result, query: query)
        }

        var lines: [String] = []
        lines.append("[DO NOT USE TOOLS - DATA BELOW]")
        lines.append("")
        lines.append("\(result.league.displayName):")

        // Final games
        if !result.finalGames.isEmpty {
            lines.append("")
            lines.append("Final:")
            for game in result.finalGames {
                lines.append("  " + formatGame(game))
            }
        }

        // Live games
        if !result.liveGames.isEmpty {
            lines.append("")
            lines.append("In Progress:")
            for game in result.liveGames {
                lines.append("  " + formatGame(game))
            }
        }

        // Scheduled games
        if !result.scheduledGames.isEmpty {
            lines.append("")
            lines.append("Upcoming:")
            for game in result.scheduledGames {
                lines.append("  " + formatGame(game))
            }
        }

        // Postponed games
        if !result.postponedGames.isEmpty {
            lines.append("")
            lines.append("Postponed:")
            for game in result.postponedGames {
                lines.append("  " + formatGame(game))
            }
        }

        lines.append("")
        lines.append("List ONLY these scores. Do not add extra text. Question: \(query)")

        return lines.joined(separator: "\n")
    }

    /// Format for brief/summary response
    static func formatBriefForLLM(result: SportsResult, query: String) -> String {
        guard !result.isEmpty else {
            return "No \(result.league.displayName) games found."
        }

        var lines: [String] = []
        lines.append("[DATA - DO NOT USE TOOLS]")
        lines.append("\(result.league.displayName): \(result.games.count) games")

        // Just show final scores briefly
        for game in result.finalGames.prefix(5) {
            if game.hasScores {
                lines.append("\(game.awayTeam) \(game.awayScore!)-\(game.homeScore!) \(game.homeTeam)")
            }
        }

        if result.liveGames.count > 0 {
            lines.append("\(result.liveGames.count) game(s) in progress")
        }

        lines.append("Question: \(query)")

        return lines.joined(separator: "\n")
    }
}
