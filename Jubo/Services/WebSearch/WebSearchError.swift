import Foundation

enum WebSearchError: LocalizedError {
    case networkUnavailable
    case quotaExceeded
    case rateLimited
    case sensitiveContent
    case noResults
    case apiError(String)
    case invalidAPIKey
    case apiKeyMissing

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "No internet connection"
        case .quotaExceeded:
            return "Monthly search limit reached"
        case .rateLimited:
            return "Please wait before searching again"
        case .sensitiveContent:
            return "Query contains personal information"
        case .noResults:
            return "No relevant results found"
        case .apiError(let message):
            return "Search error: \(message)"
        case .invalidAPIKey:
            return "Invalid API key"
        case .apiKeyMissing:
            return "API key not configured"
        }
    }
}
