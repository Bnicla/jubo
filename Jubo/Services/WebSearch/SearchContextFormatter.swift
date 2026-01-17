import Foundation

/// Response detail level for formatting and adaptive prompts.
/// Determines verbosity of search context and response length hints.
enum ResponseDetailLevel: Equatable {
    case brief      // Single fact answer (short, direct)
    case detailed   // Multi-part answer with more context
}

struct SearchContextFormatter {

    /// Maximum characters for brief search context
    private static let maxBriefContextLength = 500

    /// Maximum characters for detailed search context (increased for richer results)
    private static let maxDetailedContextLength = 1200

    /// Format search results into a context string for the LLM
    /// Adjusts detail level based on expected response type
    static func formatForLLM(
        originalQuery: String,
        results: [BraveSearchService.SearchResult],
        detailLevel: ResponseDetailLevel = .detailed,
        maxResults: Int? = nil
    ) -> String {
        guard !results.isEmpty else {
            return originalQuery
        }

        switch detailLevel {
        case .brief:
            return formatBrief(query: originalQuery, results: results)
        case .detailed:
            return formatDetailed(query: originalQuery, results: results, maxResults: maxResults ?? 2)
        }
    }

    /// Format for brief single-fact answers
    private static func formatBrief(
        query: String,
        results: [BraveSearchService.SearchResult]
    ) -> String {
        // Prefer instant answer if available
        let bestResult = results.first { $0.isInstantAnswer } ?? results.first
        guard let result = bestResult else { return query }

        let desc = truncate(result.description, to: 150)
        let title = truncate(result.title, to: 60)
        let sourceLabel = result.isInstantAnswer ? "[Direct Answer]" : "[Web]"

        let context = """
            \(sourceLabel) \(title)
            \(desc)

            Give a short, direct answer: \(query)
            """

        return truncate(context, to: maxBriefContextLength)
    }

    /// Format for detailed multi-fact answers
    private static func formatDetailed(
        query: String,
        results: [BraveSearchService.SearchResult],
        maxResults: Int
    ) -> String {
        // Categorize results by type for better organization
        let faqResults = results.filter { $0.answerType == "faq" }
        let infoboxResults = results.filter { $0.isInstantAnswer && $0.answerType != "faq" }
        let newsResults = results.filter { $0.answerType == "news" }
        let locationResults = results.filter { $0.answerType == "location" }
        let discussionResults = results.filter { $0.answerType == "discussion" }
        let webResults = results.filter { $0.answerType == "web" }

        var contextParts: [String] = []
        var resultCount = 0
        let maxTotal = maxResults + 2  // Allow a few more for variety

        // 1. FAQ - highest priority (direct Q&A)
        for result in faqResults.prefix(2) where resultCount < maxTotal {
            let desc = truncate(result.description, to: 350)
            contextParts.append("[FAQ]\n\(desc)")
            resultCount += 1
        }

        // 2. Infobox - instant answers (knowledge panels)
        for result in infoboxResults.prefix(1) where resultCount < maxTotal {
            let desc = truncate(result.description, to: 300)
            let title = truncate(result.title, to: 80)
            contextParts.append("[Direct Answer] \(title)\n\(desc)")
            resultCount += 1
        }

        // 3. News - for current events
        for result in newsResults.prefix(2) where resultCount < maxTotal {
            let desc = truncate(result.description, to: 250)
            let title = truncate(result.title, to: 80)
            contextParts.append("[News] \(title)\n\(desc)")
            resultCount += 1
        }

        // 4. Locations - for local queries
        for result in locationResults.prefix(2) where resultCount < maxTotal {
            let desc = truncate(result.description, to: 200)
            let title = truncate(result.title, to: 80)
            contextParts.append("[Location] \(title)\n\(desc)")
            resultCount += 1
        }

        // 5. Discussions - community insights
        for result in discussionResults.prefix(1) where resultCount < maxTotal {
            let desc = truncate(result.description, to: 200)
            let title = truncate(result.title, to: 80)
            contextParts.append("[Discussion] \(title)\n\(desc)")
            resultCount += 1
        }

        // 6. Web results - general information
        for result in webResults.prefix(3) where resultCount < maxTotal {
            let desc = truncate(result.description, to: 250)
            let title = truncate(result.title, to: 80)
            contextParts.append("[Web] \(title)\n\(desc)")
            resultCount += 1
        }

        let searchContext = contextParts.joined(separator: "\n\n")

        // Build instruction based on result types found
        let hasDirectAnswers = !faqResults.isEmpty || !infoboxResults.isEmpty
        let instruction: String
        if hasDirectAnswers {
            instruction = "Using the search results above (prioritize FAQ and Direct Answers), provide a helpful response to: \(query)\nInclude specific facts, numbers, dates, and details found in the results."
        } else {
            instruction = "Using the search results above, provide a helpful answer to: \(query)\nInclude specific facts, numbers, and details from the results."
        }

        let context = """
            [SEARCH RESULTS]
            \(searchContext)
            [END RESULTS]

            \(instruction)
            """

        return truncate(context, to: maxDetailedContextLength)
    }

    /// Truncate text to a maximum length
    private static func truncate(_ text: String, to length: Int) -> String {
        if text.count <= length {
            return text
        }
        return String(text.prefix(length - 3)) + "..."
    }

    /// Extract just the domain from a URL for cleaner display
    private static func extractDomain(from urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return urlString
        }
        // Remove www. prefix if present
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    /// Create a brief summary of search results for UI display
    static func briefSummary(results: [BraveSearchService.SearchResult]) -> String {
        let count = results.count
        if count == 0 {
            return "No results found"
        } else if count == 1 {
            return "Found 1 result"
        } else {
            return "Found \(count) results"
        }
    }

    /// Extract source URLs for attribution
    static func extractSources(from results: [BraveSearchService.SearchResult], maxSources: Int = 3) -> [String] {
        return Array(results.prefix(maxSources).map { $0.url })
    }
}
