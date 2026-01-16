import Foundation

struct QuerySanitizer {

    // MARK: - Result Type

    struct SanitizationResult {
        let originalQuery: String
        let sanitizedQuery: String
        let containedPII: Bool
        let piiTypesFound: [String]
        let shouldProceed: Bool  // False if too much PII or sensitive topic
    }

    // MARK: - PII Detection Patterns

    private static let piiPatterns: [(name: String, pattern: String, replacement: String)] = [
        // Email addresses
        ("email",
         #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#,
         ""),

        // Phone numbers (various formats)
        ("phone",
         #"(\+?1[-.\s]?)?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}"#,
         ""),

        // SSN
        ("ssn",
         #"\b\d{3}[-]?\d{2}[-]?\d{4}\b"#,
         ""),

        // Credit card numbers (basic pattern)
        ("credit_card",
         #"\b(?:\d{4}[-\s]?){3}\d{4}\b"#,
         ""),

        // IP addresses
        ("ip_address",
         #"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"#,
         ""),

        // Street addresses (basic US pattern)
        ("address",
         #"\d{1,5}\s+\w+\s+(street|st|avenue|ave|road|rd|drive|dr|lane|ln|way|court|ct|boulevard|blvd|circle|cir)\b"#,
         ""),

        // Zip codes (US)
        ("zipcode",
         #"\b\d{5}(-\d{4})?\b"#,
         "")
    ]

    // Name extraction patterns - remove names mentioned in context
    private static let nameContextPatterns: [String] = [
        #"my name is (\w+)"#,
        #"i am (\w+)"#,
        #"i'm (\w+)"#,
        #"call me (\w+)"#,
        #"this is (\w+) speaking"#,
        #"(\w+) here"#
    ]

    // Sensitive topics - don't search at all
    private static let sensitiveTopics: [String] = [
        "my password",
        "my passcode",
        "my pin",
        "my salary",
        "my income",
        "my bank account",
        "my account number",
        "my social security",
        "my ssn",
        "my diagnosis",
        "my medical",
        "my health condition",
        "my medication",
        "my prescription",
        "my therapist",
        "my psychiatrist",
        "my lawyer",
        "my attorney",
        "my home address",
        "my address is",
        "i live at",
        "my credit card",
        "my debit card"
    ]

    // MARK: - Public API

    static func sanitize(query: String) -> SanitizationResult {
        var sanitized = query
        var piiTypesFound: [String] = []

        // Check for sensitive topics first - don't search at all
        let lowercased = query.lowercased()
        for topic in sensitiveTopics {
            if lowercased.contains(topic) {
                return SanitizationResult(
                    originalQuery: query,
                    sanitizedQuery: "",
                    containedPII: true,
                    piiTypesFound: ["sensitive_topic"],
                    shouldProceed: false
                )
            }
        }

        // Apply regex-based PII removal
        for (name, pattern, replacement) in piiPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(sanitized.startIndex..., in: sanitized)
                if regex.firstMatch(in: sanitized, options: [], range: range) != nil {
                    piiTypesFound.append(name)
                    sanitized = regex.stringByReplacingMatches(
                        in: sanitized,
                        options: [],
                        range: NSRange(sanitized.startIndex..., in: sanitized),
                        withTemplate: replacement
                    )
                }
            }
        }

        // Extract and remove names from context
        for pattern in nameContextPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(sanitized.startIndex..., in: sanitized)
                if regex.firstMatch(in: sanitized, options: [], range: range) != nil {
                    piiTypesFound.append("name")
                    sanitized = regex.stringByReplacingMatches(
                        in: sanitized,
                        options: [],
                        range: NSRange(sanitized.startIndex..., in: sanitized),
                        withTemplate: ""
                    )
                }
            }
        }

        // Clean up multiple spaces and trim
        sanitized = sanitized.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        // If query is now too short or empty, don't proceed
        let shouldProceed = sanitized.count >= 3 && !sanitized.isEmpty

        return SanitizationResult(
            originalQuery: query,
            sanitizedQuery: sanitized,
            containedPII: !piiTypesFound.isEmpty,
            piiTypesFound: piiTypesFound,
            shouldProceed: shouldProceed
        )
    }

    /// Quick check if query likely contains PII without full sanitization
    static func mightContainPII(query: String) -> Bool {
        let lowercased = query.lowercased()

        // Quick check for sensitive topics
        for topic in sensitiveTopics {
            if lowercased.contains(topic) {
                return true
            }
        }

        // Quick check for common PII patterns
        let quickPatterns = [
            #"@[a-zA-Z0-9.-]+\.[a-zA-Z]"#,  // Email-like
            #"\d{3}[-.\s]?\d{3}[-.\s]?\d{4}"#,  // Phone-like
            #"\d{3}[-]?\d{2}[-]?\d{4}"#  // SSN-like
        ]

        for pattern in quickPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: query, options: [], range: NSRange(query.startIndex..., in: query)) != nil {
                return true
            }
        }

        return false
    }
}
