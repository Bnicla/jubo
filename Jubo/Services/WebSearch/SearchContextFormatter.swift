import Foundation

struct SearchContextFormatter {

    /// Format search results into a context string for the LLM
    /// - Parameters:
    ///   - originalQuery: The user's original question
    ///   - results: Search results from Brave API
    ///   - maxResults: Maximum number of results to include (default 3)
    /// - Returns: Formatted context string to prepend to LLM prompt
    static func formatForLLM(
        originalQuery: String,
        results: [BraveSearchService.SearchResult],
        maxResults: Int = 3
    ) -> String {
        guard !results.isEmpty else {
            return originalQuery
        }

        var context = """
        [WEB SEARCH RESULTS]
        I searched the web for information related to your question. Here are the relevant results:

        """

        for (index, result) in results.prefix(maxResults).enumerated() {
            let ageInfo = result.age.map { " (\($0))" } ?? ""

            context += """

            [\(index + 1)] \(result.title)\(ageInfo)
            Source: \(extractDomain(from: result.url))
            \(result.description)

            """
        }

        context += """

        [END SEARCH RESULTS]

        Based on the search results above, please answer the user's question.
        Synthesize the information naturally and cite sources when relevant.
        If the search results don't fully answer the question, supplement with your knowledge but note what came from the web.

        User's question: \(originalQuery)
        """

        return context
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
