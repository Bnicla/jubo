import Foundation

actor BraveSearchService {

    // MARK: - Types

    struct SearchResult: Codable, Sendable {
        let title: String
        let url: String
        let description: String
        let age: String?

        init(title: String, url: String, description: String, age: String? = nil) {
            self.title = title
            self.url = url
            self.description = description
            self.age = age
        }
    }

    // Brave API response structure
    private struct BraveResponse: Codable {
        let web: WebResults?

        struct WebResults: Codable {
            let results: [WebResult]
        }

        struct WebResult: Codable {
            let title: String
            let url: String
            let description: String
            let age: String?
        }
    }

    // MARK: - Properties

    private let baseURL = "https://api.search.brave.com/res/v1/web/search"
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 1.0  // 1 request per second

    // MARK: - Public API

    func search(query: String, apiKey: String, count: Int = 5) async throws -> [SearchResult] {
        // Rate limiting
        try await enforceRateLimit()

        // Build URL
        guard var components = URLComponents(string: baseURL) else {
            throw WebSearchError.apiError("Invalid URL")
        }

        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "safesearch", value: "moderate"),
            URLQueryItem(name: "freshness", value: "pw")  // Past week for recency
        ]

        guard let url = components.url else {
            throw WebSearchError.apiError("Failed to build URL")
        }

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.timeoutInterval = 10

        // Make request
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                throw WebSearchError.networkUnavailable
            }
            throw WebSearchError.apiError(error.localizedDescription)
        }

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebSearchError.apiError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw WebSearchError.invalidAPIKey
        case 429:
            throw WebSearchError.rateLimited
        default:
            throw WebSearchError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Parse response
        let braveResponse: BraveResponse
        do {
            braveResponse = try JSONDecoder().decode(BraveResponse.self, from: data)
        } catch {
            throw WebSearchError.apiError("Failed to parse response")
        }

        guard let results = braveResponse.web?.results, !results.isEmpty else {
            throw WebSearchError.noResults
        }

        // Convert to our SearchResult type
        return results.map { result in
            SearchResult(
                title: result.title,
                url: result.url,
                description: result.description,
                age: result.age
            )
        }
    }

    // MARK: - Rate Limiting

    private func enforceRateLimit() async throws {
        if let lastRequest = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastRequest)
            if elapsed < minRequestInterval {
                let waitTime = minRequestInterval - elapsed
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }
}
