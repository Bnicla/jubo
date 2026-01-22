import Foundation

actor BraveSearchService {

    // MARK: - Types

    struct SearchResult: Codable, Sendable {
        let title: String
        let url: String
        let description: String
        let age: String?
        let isInstantAnswer: Bool  // True for infobox results (direct answers)
        let answerType: String?    // Type of instant answer (weather, knowledge, etc.)

        init(title: String, url: String, description: String, age: String? = nil, isInstantAnswer: Bool = false, answerType: String? = nil) {
            self.title = title
            self.url = url
            self.description = description
            self.age = age
            self.isInstantAnswer = isInstantAnswer
            self.answerType = answerType
        }
    }

    // Brave API response structure - captures all available result types
    private struct BraveResponse: Codable {
        let web: WebResults?
        let news: NewsResults?
        let videos: VideoResults?
        let discussions: DiscussionResults?
        let faq: FAQResults?
        let locations: LocationResults?
        let infobox: Infobox?
        let mixed: MixedResults?
        let query: QueryInfo?

        struct WebResults: Codable {
            let results: [WebResult]
        }

        struct WebResult: Codable {
            let title: String
            let url: String
            let description: String
            let age: String?
            let extraSnippets: [String]?  // Up to 5 additional excerpts

            enum CodingKeys: String, CodingKey {
                case title, url, description, age
                case extraSnippets = "extra_snippets"
            }
        }

        struct NewsResults: Codable {
            let results: [NewsResult]
        }

        struct NewsResult: Codable {
            let title: String
            let url: String
            let description: String
            let age: String?
            let source: String?
        }

        struct VideoResults: Codable {
            let results: [VideoResult]
        }

        struct VideoResult: Codable {
            let title: String
            let url: String
            let description: String?
            let age: String?
            let creator: String?
        }

        struct DiscussionResults: Codable {
            let results: [DiscussionResult]
        }

        struct DiscussionResult: Codable {
            let title: String
            let url: String
            let description: String
            let age: String?
            let forum: String?
        }

        struct FAQResults: Codable {
            let results: [FAQResult]
        }

        struct FAQResult: Codable {
            let question: String
            let answer: String
            let url: String?
            let title: String?
        }

        struct LocationResults: Codable {
            let results: [LocationResult]
        }

        struct LocationResult: Codable {
            let title: String
            let url: String?
            let description: String?
            let address: String?
            let phone: String?
            let rating: Double?
            let reviewCount: Int?

            enum CodingKeys: String, CodingKey {
                case title, url, description, address, phone, rating
                case reviewCount = "review_count"
            }
        }

        // Mixed results show Brave's recommended display order
        struct MixedResults: Codable {
            let main: [MixedRef]?
            let top: [MixedRef]?
            let side: [MixedRef]?

            struct MixedRef: Codable {
                let type: String      // "web", "news", "videos", etc.
                let index: Int?       // Index into the respective results array
                let all: Bool?        // If true, include all results of this type
            }
        }

        // Query info including spellcheck suggestions
        struct QueryInfo: Codable {
            let original: String?
            let altered: String?           // Spellchecked/corrected query
            let spellcheckOff: Bool?

            enum CodingKeys: String, CodingKey {
                case original, altered
                case spellcheckOff = "spellcheck_off"
            }
        }

        // Infobox contains instant answer data (weather, knowledge panels, etc.)
        struct Infobox: Codable {
            let results: [InfoboxResult]?
            let type: String?

            struct InfoboxResult: Codable {
                let title: String?
                let description: String?
                let longDesc: String?
                let url: String?
                let data: GenericData?

                enum CodingKeys: String, CodingKey {
                    case title, description, url, data
                    case longDesc = "long_desc"
                }
            }

            struct GenericData: Codable {
                let values: [String: AnyCodableValue]

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
                    var dict: [String: AnyCodableValue] = [:]
                    for key in container.allKeys {
                        if let value = try? container.decode(String.self, forKey: key) {
                            dict[key.stringValue] = .string(value)
                        } else if let value = try? container.decode(Int.self, forKey: key) {
                            dict[key.stringValue] = .int(value)
                        } else if let value = try? container.decode(Double.self, forKey: key) {
                            dict[key.stringValue] = .double(value)
                        } else if let value = try? container.decode(Bool.self, forKey: key) {
                            dict[key.stringValue] = .bool(value)
                        } else if let value = try? container.decode([String].self, forKey: key) {
                            dict[key.stringValue] = .stringArray(value)
                        }
                    }
                    self.values = dict
                }

                func encode(to encoder: Encoder) throws {}
            }

            struct DynamicCodingKey: CodingKey {
                var stringValue: String
                var intValue: Int?
                init?(stringValue: String) { self.stringValue = stringValue }
                init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
            }
        }
    }

    // Represents any JSON value type
    enum AnyCodableValue: Codable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case stringArray([String])

        var stringRepresentation: String {
            switch self {
            case .string(let s): return s
            case .int(let i): return String(i)
            case .double(let d): return String(format: "%.1f", d)
            case .bool(let b): return b ? "Yes" : "No"
            case .stringArray(let arr): return arr.joined(separator: ", ")
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) { self = .string(s) }
            else if let i = try? container.decode(Int.self) { self = .int(i) }
            else if let d = try? container.decode(Double.self) { self = .double(d) }
            else if let b = try? container.decode(Bool.self) { self = .bool(b) }
            else if let arr = try? container.decode([String].self) { self = .stringArray(arr) }
            else { self = .string("") }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let s): try container.encode(s)
            case .int(let i): try container.encode(i)
            case .double(let d): try container.encode(d)
            case .bool(let b): try container.encode(b)
            case .stringArray(let arr): try container.encode(arr)
            }
        }
    }

    // MARK: - Properties

    private let webSearchURL = "https://api.search.brave.com/res/v1/web/search"
    private let newsSearchURL = "https://api.search.brave.com/res/v1/news/search"
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 1.0  // 1 request per second

    /// Freshness options for search results
    enum Freshness: String {
        case pastDay = "pd"
        case pastWeek = "pw"
        case pastMonth = "pm"
        case pastYear = "py"
        case none = ""  // No freshness filter

        /// Determine appropriate freshness based on query content
        static func forQuery(_ query: String) -> Freshness {
            let lower = query.lowercased()

            // Sports scores, live events, breaking news need past day
            let urgentKeywords = [
                // Live/breaking
                "breaking", "just happened", "right now", "this morning", "tonight", "live",
                // Sports (scores change hourly)
                "score", "result", "results", "game today", "match today", "who won", "final score",
                "champions league", "premier league", "nba", "nfl", "mlb", "nhl",
                // Time-sensitive
                "today"
            ]
            if urgentKeywords.contains(where: { lower.contains($0) }) {
                return .pastDay
            }

            // Weather, current events need past week
            let recentKeywords = ["weather", "forecast", "game", "match", "news", "latest", "current", "tomorrow", "this week"]
            if recentKeywords.contains(where: { lower.contains($0) }) {
                return .pastWeek
            }

            // Historical or evergreen queries don't need freshness filter
            let evergreenKeywords = ["how to", "what is", "explain", "history of", "definition"]
            if evergreenKeywords.contains(where: { lower.contains($0) }) {
                return .none
            }

            // Default to past month for general queries
            return .pastMonth
        }
    }

    // MARK: - Public API

    func search(query: String, apiKey: String, count: Int = 5, freshness: Freshness? = nil) async throws -> [SearchResult] {
        // Rate limiting
        try await enforceRateLimit()

        // Determine freshness - use provided value or auto-detect from query
        let effectiveFreshness = freshness ?? Freshness.forQuery(query)

        // Build URL
        guard var components = URLComponents(string: webSearchURL) else {
            throw WebSearchError.apiError("Invalid URL")
        }

        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "safesearch", value: "moderate"),
            URLQueryItem(name: "spellcheck", value: "1"),           // Enable spellcheck
            URLQueryItem(name: "extra_snippets", value: "true"),    // Get up to 5 extra snippets per result
            URLQueryItem(name: "text_decorations", value: "false")  // Plain text without HTML markup
        ]

        // Only add freshness if specified (some queries work better without it)
        if effectiveFreshness != .none {
            queryItems.append(URLQueryItem(name: "freshness", value: effectiveFreshness.rawValue))
        }

        components.queryItems = queryItems
        print("[BraveSearch] Query: '\(query)' | Freshness: \(effectiveFreshness.rawValue.isEmpty ? "none" : effectiveFreshness.rawValue)")

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
            // Log raw response for debugging
            if let rawString = String(data: data, encoding: .utf8) {
                print("[BraveSearch] Failed to parse. Raw response (first 500 chars): \(String(rawString.prefix(500)))")
            }
            throw WebSearchError.apiError("Failed to parse response")
        }

        var searchResults: [SearchResult] = []

        // Log spellcheck corrections
        if let queryInfo = braveResponse.query {
            if let altered = queryInfo.altered, let original = queryInfo.original, altered != original {
                print("[BraveSearch] Spellcheck: '\(original)' → '\(altered)'")
            }
        }

        // 1. FAQ results - highest priority, direct Q&A pairs
        if let faqResults = braveResponse.faq?.results {
            print("[BraveSearch] Found \(faqResults.count) FAQ results")
            for faq in faqResults.prefix(2) {
                let description = "Q: \(faq.question)\nA: \(faq.answer)"
                print("[BraveSearch] FAQ: \(faq.question.prefix(50))...")
                searchResults.append(SearchResult(
                    title: faq.title ?? "FAQ",
                    url: faq.url ?? "",
                    description: description,
                    isInstantAnswer: true,
                    answerType: "faq"
                ))
            }
        }

        // 2. Infobox - instant answers (weather, knowledge panels, etc.)
        if let infobox = braveResponse.infobox {
            let answerType = infobox.type ?? "infobox"
            print("[BraveSearch] Found infobox type: \(answerType)")

            if let infoResults = infobox.results {
                for info in infoResults {
                    var descParts: [String] = []

                    if let desc = info.description { descParts.append(desc) }
                    if let longDesc = info.longDesc { descParts.append(longDesc) }

                    if let data = info.data {
                        let formattedData = formatInfoboxData(data.values)
                        if !formattedData.isEmpty { descParts.append(formattedData) }
                    }

                    let description = descParts.joined(separator: ". ")
                    if !description.isEmpty {
                        print("[BraveSearch] Infobox [\(answerType)]: \(info.title ?? "no title") - \(description.prefix(100))...")
                        searchResults.append(SearchResult(
                            title: info.title ?? "Information",
                            url: info.url ?? "",
                            description: description,
                            isInstantAnswer: true,
                            answerType: answerType
                        ))
                    }
                }
            }
        }

        // 3. News results - for current events
        if let newsResults = braveResponse.news?.results {
            print("[BraveSearch] Found \(newsResults.count) news results")
            for news in newsResults.prefix(3) {
                var description = news.description
                if let source = news.source {
                    description = "[\(source)] \(description)"
                }
                if let age = news.age {
                    description += " (\(age))"
                }
                print("[BraveSearch] News: \(news.title.prefix(50))...")
                searchResults.append(SearchResult(
                    title: news.title,
                    url: news.url,
                    description: description,
                    age: news.age,
                    isInstantAnswer: false,
                    answerType: "news"
                ))
            }
        }

        // 4. Locations - for local queries
        if let locationResults = braveResponse.locations?.results {
            print("[BraveSearch] Found \(locationResults.count) location results")
            for loc in locationResults.prefix(3) {
                var descParts: [String] = []
                if let address = loc.address { descParts.append(address) }
                if let phone = loc.phone { descParts.append("📞 \(phone)") }
                if let rating = loc.rating {
                    let stars = String(repeating: "★", count: Int(rating.rounded()))
                    descParts.append("\(stars) \(String(format: "%.1f", rating))")
                    if let reviews = loc.reviewCount {
                        descParts[descParts.count - 1] += " (\(reviews) reviews)"
                    }
                }
                let description = descParts.joined(separator: " | ")
                print("[BraveSearch] Location: \(loc.title) - \(description.prefix(60))...")
                searchResults.append(SearchResult(
                    title: loc.title,
                    url: loc.url ?? "",
                    description: description,
                    isInstantAnswer: false,
                    answerType: "location"
                ))
            }
        }

        // 5. Discussions - forum/community results
        if let discussionResults = braveResponse.discussions?.results {
            print("[BraveSearch] Found \(discussionResults.count) discussion results")
            for disc in discussionResults.prefix(2) {
                var description = disc.description
                if let forum = disc.forum {
                    description = "[\(forum)] \(description)"
                }
                print("[BraveSearch] Discussion: \(disc.title.prefix(50))...")
                searchResults.append(SearchResult(
                    title: disc.title,
                    url: disc.url,
                    description: description,
                    age: disc.age,
                    isInstantAnswer: false,
                    answerType: "discussion"
                ))
            }
        }

        // 6. Web results - include extra snippets for richer context
        if let webResults = braveResponse.web?.results {
            print("[BraveSearch] Found \(webResults.count) web results")
            for (index, result) in webResults.prefix(5).enumerated() {
                // Combine main description with extra snippets
                var fullDescription = result.description
                if let extras = result.extraSnippets, !extras.isEmpty {
                    let snippetText = extras.prefix(2).joined(separator: " ... ")
                    fullDescription += " ... \(snippetText)"
                    print("[BraveSearch] Web[\(index)]: \(result.title.prefix(40))... (+\(extras.count) snippets)")
                } else {
                    print("[BraveSearch] Web[\(index)]: \(result.title.prefix(40))...")
                }

                searchResults.append(SearchResult(
                    title: result.title,
                    url: result.url,
                    description: fullDescription,
                    age: result.age,
                    isInstantAnswer: false,
                    answerType: "web"
                ))
            }
        }

        // Log mixed results priority if available
        if let mixed = braveResponse.mixed?.main {
            let types = mixed.prefix(5).map { $0.type }
            print("[BraveSearch] Mixed priority: \(types.joined(separator: " → "))")
        }

        guard !searchResults.isEmpty else {
            throw WebSearchError.noResults
        }

        return searchResults
    }

    /// Dedicated news search using Brave's News Search API endpoint
    /// Better for current events, breaking news, and time-sensitive queries
    func searchNews(query: String, apiKey: String, count: Int = 10, freshness: Freshness? = nil) async throws -> [SearchResult] {
        // Rate limiting
        try await enforceRateLimit()

        // Determine freshness - news typically needs recent results
        let effectiveFreshness = freshness ?? .pastWeek

        // Build URL
        guard var components = URLComponents(string: newsSearchURL) else {
            throw WebSearchError.apiError("Invalid URL")
        }

        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(min(count, 50))),  // News API supports up to 50
            URLQueryItem(name: "safesearch", value: "moderate"),
            URLQueryItem(name: "spellcheck", value: "1"),
            URLQueryItem(name: "extra_snippets", value: "true"),
            URLQueryItem(name: "text_decorations", value: "false")
        ]

        // Add freshness filter
        if effectiveFreshness != .none {
            queryItems.append(URLQueryItem(name: "freshness", value: effectiveFreshness.rawValue))
        }

        components.queryItems = queryItems
        print("[BraveNews] Query: '\(query)' | Freshness: \(effectiveFreshness.rawValue.isEmpty ? "none" : effectiveFreshness.rawValue)")

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

        // Parse response - News API returns results directly
        let newsResponse: NewsSearchResponse
        do {
            newsResponse = try JSONDecoder().decode(NewsSearchResponse.self, from: data)
        } catch {
            if let rawString = String(data: data, encoding: .utf8) {
                print("[BraveNews] Failed to parse. Raw response (first 500 chars): \(String(rawString.prefix(500)))")
            }
            throw WebSearchError.apiError("Failed to parse response")
        }

        var searchResults: [SearchResult] = []

        if let results = newsResponse.results {
            print("[BraveNews] Found \(results.count) news results")
            for news in results {
                var description = news.description
                if let source = news.source {
                    description = "[\(source)] \(description)"
                }
                if let age = news.age {
                    description += " (\(age))"
                }

                // Include extra snippets if available
                if let extras = news.extraSnippets, !extras.isEmpty {
                    description += " ... \(extras.prefix(2).joined(separator: " ... "))"
                }

                searchResults.append(SearchResult(
                    title: news.title,
                    url: news.url,
                    description: description,
                    age: news.age,
                    isInstantAnswer: false,
                    answerType: "news"
                ))
            }
        }

        guard !searchResults.isEmpty else {
            throw WebSearchError.noResults
        }

        return searchResults
    }

    // News Search API response structure
    private struct NewsSearchResponse: Codable {
        let results: [NewsArticle]?
        let query: QueryInfo?

        struct NewsArticle: Codable {
            let title: String
            let url: String
            let description: String
            let age: String?
            let source: String?
            let extraSnippets: [String]?

            enum CodingKeys: String, CodingKey {
                case title, url, description, age, source
                case extraSnippets = "extra_snippets"
            }
        }

        struct QueryInfo: Codable {
            let original: String?
            let altered: String?
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

    // MARK: - Helpers

    /// Format infobox key-value data into a readable string
    private func formatInfoboxData(_ values: [String: AnyCodableValue]) -> String {
        // Keys to prioritize displaying first (common across many infobox types)
        let priorityKeys = ["temperature", "temp", "value", "answer", "result", "price", "score",
                           "date", "time", "location", "status", "conditions", "weather"]

        // Keys to skip (internal/technical)
        let skipKeys = ["id", "type", "source", "url", "image", "thumbnail", "icon"]

        var parts: [String] = []

        // Add priority keys first
        for key in priorityKeys {
            if let value = values[key] {
                let formattedKey = formatKeyName(key)
                parts.append("\(formattedKey): \(value.stringRepresentation)")
            }
        }

        // Add remaining keys
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            if priorityKeys.contains(key.lowercased()) || skipKeys.contains(key.lowercased()) {
                continue
            }
            let formattedKey = formatKeyName(key)
            parts.append("\(formattedKey): \(value.stringRepresentation)")
        }

        return parts.joined(separator: ", ")
    }

    /// Convert camelCase or snake_case key to readable format
    private func formatKeyName(_ key: String) -> String {
        // Handle snake_case
        let result = key.replacingOccurrences(of: "_", with: " ")

        // Handle camelCase - insert space before capitals
        var formatted = ""
        for (index, char) in result.enumerated() {
            if char.isUppercase && index > 0 {
                formatted += " "
            }
            formatted += String(char)
        }

        // Capitalize first letter
        return formatted.prefix(1).uppercased() + formatted.dropFirst()
    }
}
