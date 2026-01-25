//
//  WeatherKitService.swift
//  Jubo
//
//  Service for fetching weather data using Apple's WeatherKit framework.
//  Provides current conditions and 7-day forecasts formatted for LLM context injection.
//
//  Requirements:
//  - WeatherKit entitlement in Jubo.entitlements
//  - WeatherKit capability enabled in Apple Developer Portal
//  - Active Apple Developer Program membership
//

import Foundation
import WeatherKit
import CoreLocation

/// Service for fetching weather data using Apple's WeatherKit.
///
/// This actor-based service handles:
/// - Geocoding location strings to coordinates using CLGeocoder
/// - Fetching weather data from WeatherKit
/// - Formatting weather data for LLM context injection
///
/// Usage:
/// ```swift
/// let service = WeatherKitService()
/// let weather = try await service.fetchWeather(for: "Boston")
/// let context = weather.formatForLLM(query: "What's the weather?")
/// ```
actor WeatherKitService {

    // MARK: - Types

    /// Formatted weather data ready for display or LLM context injection.
    /// All values are pre-formatted as strings respecting user preferences (e.g., Celsius vs Fahrenheit).
    struct WeatherData: Sendable {
        let location: String
        let current: CurrentConditions
        let hourly: [HourlyForecast]
        let daily: [DailyForecast]

        /// Current weather conditions at the requested location.
        struct CurrentConditions: Sendable {
            let temperature: String          // e.g., "72°F"
            let feelsLike: String            // e.g., "75°F"
            let condition: String            // e.g., "Partly Cloudy"
            let conditionSymbol: String      // SF Symbol name, e.g., "cloud.sun"
            let humidity: String             // e.g., "65%"
            let windSpeed: String            // e.g., "12 mph"
            let windDirection: String        // e.g., "NW"
            let uvIndex: String              // e.g., "5 (Moderate)"
            let visibility: String           // e.g., "10 mi"
        }

        /// Hourly forecast for the next 12 hours.
        struct HourlyForecast: Sendable {
            let time: String                 // e.g., "3PM"
            let temperature: String
            let condition: String
            let conditionSymbol: String
            let precipitationChance: String  // e.g., "20%"
        }

        /// Daily forecast for the next 7 days.
        struct DailyForecast: Sendable {
            let date: String                 // e.g., "Jan 17"
            let dayOfWeek: String            // e.g., "Friday"
            let highTemperature: String
            let lowTemperature: String
            let condition: String
            let conditionSymbol: String
            let precipitationChance: String
            let sunrise: String              // e.g., "6AM"
            let sunset: String               // e.g., "5PM"
        }

        /// Format weather data as context string for LLM prompt injection.
        /// - Parameter query: The original user query to append as instruction
        /// - Returns: Formatted string with current conditions and 7-day forecast
        func formatForLLM(query: String) -> String {
            var parts: [String] = []

            // Current conditions
            parts.append("[CURRENT WEATHER - \(location)]")
            parts.append("Temperature: \(current.temperature) (feels like \(current.feelsLike))")
            parts.append("Conditions: \(current.condition)")
            parts.append("Humidity: \(current.humidity) | Wind: \(current.windSpeed) \(current.windDirection)")
            parts.append("UV Index: \(current.uvIndex) | Visibility: \(current.visibility)")

            // Daily forecast (for "this weekend" type queries)
            if !daily.isEmpty {
                parts.append("")
                parts.append("[FORECAST]")
                for day in daily.prefix(7) {
                    parts.append("\(day.dayOfWeek): \(day.highTemperature)/\(day.lowTemperature) - \(day.condition)")
                    if day.precipitationChance != "0%" {
                        parts[parts.count - 1] += " (\(day.precipitationChance) precip)"
                    }
                }
            }

            parts.append("")
            parts.append("Based on this weather data, answer: \(query)")

            return parts.joined(separator: "\n")
        }
    }

    /// Errors that can occur during weather fetching.
    enum WeatherError: Error, LocalizedError {
        /// Geocoding failed to convert location string to coordinates
        case geocodingFailed(String)
        /// WeatherKit API call failed
        case weatherFetchFailed(String)
        /// No matching location found for the provided string
        case locationNotFound
        /// WeatherKit service is unavailable (e.g., no network, no entitlement)
        case serviceUnavailable

        var errorDescription: String? {
            switch self {
            case .geocodingFailed(let reason):
                return "Could not find location: \(reason)"
            case .weatherFetchFailed(let reason):
                return "Weather fetch failed: \(reason)"
            case .locationNotFound:
                return "Location not found"
            case .serviceUnavailable:
                return "Weather service unavailable. Please check that WeatherKit is enabled in your Apple Developer account."
            }
        }

        /// Check if this error should trigger a fallback to web search
        var shouldFallbackToWebSearch: Bool {
            switch self {
            case .serviceUnavailable, .weatherFetchFailed:
                return true
            case .geocodingFailed, .locationNotFound:
                return false
            }
        }
    }

    // MARK: - Properties

    private let weatherService = WeatherService.shared
    private let geocoder = CLGeocoder()
    private let temperatureFormatter: MeasurementFormatter
    private let dateFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    private let percentFormatter: NumberFormatter

    // MARK: - Initialization

    init() {
        temperatureFormatter = MeasurementFormatter()
        temperatureFormatter.unitStyle = .short
        temperatureFormatter.numberFormatter.maximumFractionDigits = 0

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"

        timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "ha"

        percentFormatter = NumberFormatter()
        percentFormatter.numberStyle = .percent
        percentFormatter.maximumFractionDigits = 0
    }

    // MARK: - Public API

    /// Check if WeatherKit service is available
    /// - Returns: true if WeatherKit is properly configured and available
    func isAvailable() async -> Bool {
        do {
            // Try to get attribution - this will fail if WeatherKit isn't configured
            _ = try await weatherService.attribution
            return true
        } catch {
            print("[Weather] WeatherKit not available: \(error.localizedDescription)")
            return false
        }
    }

    /// Fetch weather for a location string (city name, address, etc.)
    /// - Parameters:
    ///   - locationString: City name or address to fetch weather for
    ///   - useCelsius: Whether to format temperatures in Celsius (true) or Fahrenheit (false)
    func fetchWeather(for locationString: String, useCelsius: Bool = true) async throws -> WeatherData {
        print("[Weather] Fetching weather for: \(locationString) (useCelsius: \(useCelsius))")

        // Check if WeatherKit is available before proceeding
        guard await isAvailable() else {
            print("[Weather] WeatherKit service not available")
            throw WeatherError.serviceUnavailable
        }

        // Geocode the location string to coordinates
        let location = try await geocode(locationString)
        print("[Weather] Geocoded to: \(location.coordinate.latitude), \(location.coordinate.longitude)")

        // Fetch weather from WeatherKit
        let weather: Weather
        do {
            weather = try await weatherService.weather(for: location)
        } catch {
            print("[Weather] WeatherKit error: \(error.localizedDescription)")
            // Check if this is an authorization/configuration error
            let nsError = error as NSError
            if nsError.domain == "WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors" ||
               nsError.code == 2 || // Common authorization error code
               error.localizedDescription.lowercased().contains("unauthorized") ||
               error.localizedDescription.lowercased().contains("not authorized") {
                throw WeatherError.serviceUnavailable
            }
            throw WeatherError.weatherFetchFailed(error.localizedDescription)
        }

        // Format the response with the specified temperature unit
        let weatherData = formatWeather(weather, locationName: locationString, useCelsius: useCelsius)
        print("[Weather] Successfully fetched weather data")

        return weatherData
    }

    /// Extract location from a weather query
    /// Examples: "weather in Boston" → "Boston", "What's the weather like in NYC?" → "NYC"
    func extractLocation(from query: String) -> String? {
        let patterns = [
            "weather (?:in|for|at) ([\\w\\s,]+)",
            "(?:in|for|at) ([\\w\\s,]+) weather",
            "([\\w\\s,]+) weather",
            "weather ([\\w\\s,]+)"
        ]

        let lowercased = query.lowercased()

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: lowercased) {
                let location = String(lowercased[range])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "?.,!"))

                // Filter out common non-location words
                let nonLocationWords = ["today", "tomorrow", "weekend", "week", "now", "like", "this", "the", "be"]
                if !nonLocationWords.contains(location) && location.count > 1 {
                    return location
                }
            }
        }

        return nil
    }

    // MARK: - Private Methods

    /// Convert a location string (city name, address) to CLLocation coordinates.
    /// - Parameter locationString: Human-readable location (e.g., "Boston, MA")
    /// - Returns: CLLocation with latitude/longitude
    /// - Throws: WeatherError.locationNotFound or WeatherError.geocodingFailed
    private func geocode(_ locationString: String) async throws -> CLLocation {
        do {
            let placemarks = try await geocoder.geocodeAddressString(locationString)
            guard let placemark = placemarks.first,
                  let location = placemark.location else {
                throw WeatherError.locationNotFound
            }
            return location
        } catch let error as WeatherError {
            throw error
        } catch {
            throw WeatherError.geocodingFailed(error.localizedDescription)
        }
    }

    /// Transform raw WeatherKit data into formatted WeatherData struct.
    /// - Parameters:
    ///   - weather: Raw Weather object from WeatherKit
    ///   - locationName: Display name for the location
    ///   - useCelsius: Whether to format temperatures in Celsius
    /// - Returns: Formatted WeatherData with string values
    private func formatWeather(_ weather: Weather, locationName: String, useCelsius: Bool) -> WeatherData {
        let current = weather.currentWeather
        let hourly = weather.hourlyForecast
        let daily = weather.dailyForecast

        // Format current conditions
        let currentConditions = WeatherData.CurrentConditions(
            temperature: formatTemperature(current.temperature, useCelsius: useCelsius),
            feelsLike: formatTemperature(current.apparentTemperature, useCelsius: useCelsius),
            condition: current.condition.description,
            conditionSymbol: current.symbolName,
            humidity: formatPercent(current.humidity),
            windSpeed: formatWindSpeed(current.wind.speed),
            windDirection: formatWindDirection(current.wind.compassDirection),
            uvIndex: "\(current.uvIndex.value) (\(current.uvIndex.category))",
            visibility: formatDistance(current.visibility)
        )

        // Format hourly forecast (next 12 hours)
        let hourlyForecasts: [WeatherData.HourlyForecast] = hourly.prefix(12).map { hour in
            WeatherData.HourlyForecast(
                time: timeFormatter.string(from: hour.date),
                temperature: formatTemperature(hour.temperature, useCelsius: useCelsius),
                condition: hour.condition.description,
                conditionSymbol: hour.symbolName,
                precipitationChance: formatPercent(hour.precipitationChance)
            )
        }

        // Format daily forecast (next 7 days)
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"

        let dailyForecasts: [WeatherData.DailyForecast] = daily.prefix(7).map { day in
            WeatherData.DailyForecast(
                date: dateFormatter.string(from: day.date),
                dayOfWeek: dayFormatter.string(from: day.date),
                highTemperature: formatTemperature(day.highTemperature, useCelsius: useCelsius),
                lowTemperature: formatTemperature(day.lowTemperature, useCelsius: useCelsius),
                condition: day.condition.description,
                conditionSymbol: day.symbolName,
                precipitationChance: formatPercent(day.precipitationChance),
                sunrise: day.sun.sunrise.map { timeFormatter.string(from: $0) } ?? "N/A",
                sunset: day.sun.sunset.map { timeFormatter.string(from: $0) } ?? "N/A"
            )
        }

        return WeatherData(
            location: locationName.capitalized,
            current: currentConditions,
            hourly: hourlyForecasts,
            daily: dailyForecasts
        )
    }

    private func formatTemperature(_ temp: Measurement<UnitTemperature>, useCelsius: Bool) -> String {
        let converted = useCelsius ? temp.converted(to: .celsius) : temp.converted(to: .fahrenheit)
        return temperatureFormatter.string(from: converted)
    }

    private func formatPercent(_ value: Double) -> String {
        return "\(Int(value * 100))%"
    }

    private func formatWindSpeed(_ speed: Measurement<UnitSpeed>) -> String {
        let mph = speed.converted(to: .milesPerHour)
        return "\(Int(mph.value)) mph"
    }

    private func formatWindDirection(_ direction: Wind.CompassDirection) -> String {
        return direction.abbreviation
    }

    private func formatDistance(_ distance: Measurement<UnitLength>) -> String {
        let miles = distance.converted(to: .miles)
        return "\(Int(miles.value)) mi"
    }
}
