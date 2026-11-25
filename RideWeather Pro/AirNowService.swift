//
//  AirNowService.swift
//  RideWeather Pro
//

import Foundation

// MARK: - Models
//
// AirNow retired the `observation/latLong/current` and `forecast/latLong`
// web services on 2026-10-01 (HTTP 410; see docs.airnowapi.org/docs/
// AirNowAPIUpdates2026June.pdf). Their replacements,
// `observation/current/ziplatlong` and `forecast/current`, return camelCase
// keys and a flatter shape (no nested Category, no lat/long). Only the fields
// the app reads are required; the rest are optional so a missing field
// doesn't fail the whole decode.

/// One per-pollutant NowCast reading from the closest monitoring site.
struct AirNowObservation: Codable {
    let dateObserved: String?
    /// Local hour, e.g. "15:00".
    let hourObserved: String?
    let localTimeZone: String?
    let reportingArea: String?
    let siteName: String?
    let parameterName: String
    /// NowCast AQI (EPA 0–500); -1 when the service sends no value.
    let aqi: Int
    let categoryName: String?

    enum CodingKeys: String, CodingKey {
        case dateObserved
        case hourObserved
        case localTimeZone
        case reportingArea = "reportingAreaName"
        case siteName
        case parameterName
        case aqi = "nowcastAQI"
        case categoryName = "aqiCategoryName"
    }

    init(dateObserved: String? = nil, hourObserved: String? = nil, localTimeZone: String? = nil,
         reportingArea: String? = nil, siteName: String? = nil,
         parameterName: String, aqi: Int, categoryName: String? = nil) {
        self.dateObserved = dateObserved
        self.hourObserved = hourObserved
        self.localTimeZone = localTimeZone
        self.reportingArea = reportingArea
        self.siteName = siteName
        self.parameterName = parameterName
        self.aqi = aqi
        self.categoryName = categoryName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dateObserved = try c.decodeIfPresent(String.self, forKey: .dateObserved)
        hourObserved = try c.decodeIfPresent(String.self, forKey: .hourObserved)
        localTimeZone = try c.decodeIfPresent(String.self, forKey: .localTimeZone)
        reportingArea = try c.decodeIfPresent(String.self, forKey: .reportingArea)
        siteName = try c.decodeIfPresent(String.self, forKey: .siteName)
        parameterName = try c.decodeIfPresent(String.self, forKey: .parameterName) ?? ""
        aqi = (try? c.decodeIfPresent(Int.self, forKey: .aqi)) ?? -1
        categoryName = try c.decodeIfPresent(String.self, forKey: .categoryName)
    }
}

/// One per-pollutant daily forecast for a reporting area.
struct AirNowForecastEntry: Codable {
    let dateIssue: String?
    /// Local calendar date the forecast applies to ("yyyy-MM-dd").
    let dateForecast: String
    let reportingArea: String?
    let stateCode: String?
    let parameterName: String
    let aqi: Int          // -1 means "not forecast" — filter before use
    let categoryNumber: Int?
    let categoryName: String?
    let actionDay: Bool?
    let discussion: String?

    enum CodingKeys: String, CodingKey {
        case dateIssue
        case dateForecast = "dateValid"
        case reportingArea
        case stateCode
        case parameterName
        case aqi
        case categoryNumber
        case categoryName
        case actionDay
        case discussion
    }

    init(dateIssue: String? = nil, dateForecast: String, reportingArea: String? = nil,
         stateCode: String? = nil, parameterName: String, aqi: Int,
         categoryNumber: Int? = nil, categoryName: String? = nil,
         actionDay: Bool? = nil, discussion: String? = nil) {
        self.dateIssue = dateIssue
        self.dateForecast = dateForecast
        self.reportingArea = reportingArea
        self.stateCode = stateCode
        self.parameterName = parameterName
        self.aqi = aqi
        self.categoryNumber = categoryNumber
        self.categoryName = categoryName
        self.actionDay = actionDay
        self.discussion = discussion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dateIssue = try c.decodeIfPresent(String.self, forKey: .dateIssue)
        dateForecast = try c.decodeIfPresent(String.self, forKey: .dateForecast) ?? ""
        reportingArea = try c.decodeIfPresent(String.self, forKey: .reportingArea)
        stateCode = try c.decodeIfPresent(String.self, forKey: .stateCode)
        parameterName = try c.decodeIfPresent(String.self, forKey: .parameterName) ?? ""
        aqi = (try? c.decodeIfPresent(Int.self, forKey: .aqi)) ?? -1
        categoryNumber = try? c.decodeIfPresent(Int.self, forKey: .categoryNumber)
        categoryName = try c.decodeIfPresent(String.self, forKey: .categoryName)
        actionDay = try? c.decodeIfPresent(Bool.self, forKey: .actionDay)
        discussion = try c.decodeIfPresent(String.self, forKey: .discussion)
    }
}

// MARK: - Service

/// Official US EPA AirNow air quality: station-based NowCast observations and
/// daily per-pollutant AQI forecasts (~6 days). Station data captures smoke
/// events that model products (OpenWeather, CAMS) badly understate — during
/// the 2026-07-17 hazardous episode OpenWeather implied AQI 64 while AirNow
/// reported 296. US coverage only: an empty response means no reporting area
/// within range, and callers fall back to the OpenWeather pipeline.
final class AirNowService {
    static let shared = AirNowService()

    private var config: [String: String]?
    private var apiKey: String {
        return config?["AirNowApiKey"] ?? "INVALID_API"
    }
    private let baseURL = "https://www.airnowapi.org/aq"
    private let cache = NSCache<NSString, CachedAirNowData>()
    private let cacheMaxAge: TimeInterval = 1800 // 30 minutes

    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    init() {
        loadConfig()
    }

    /// Current per-pollutant NowCast observations for the nearest reporting
    /// area (25-mile search radius). Empty when no US reporting area is near.
    func fetchCurrentObservations(lat: Double, lon: Double) async throws -> [AirNowObservation] {
        let cacheKey = Self.cacheKey("airnow_current", lat, lon)
        if let cached = cache.object(forKey: cacheKey),
           !cached.isExpired(maxAge: cacheMaxAge),
           let observations = cached.observations {
            return observations
        }

        guard let url = URL(string: "\(baseURL)/observation/current/ziplatlong/?format=application/json&latitude=\(lat)&longitude=\(lon)&distance=25&API_KEY=\(apiKey)") else {
            throw URLError(.badURL)
        }

        let observations: [AirNowObservation] = try await fetchJSON(from: url)
        cache.setObject(CachedAirNowData(observations: observations, forecasts: nil), forKey: cacheKey)
        return observations
    }

    /// Daily per-pollutant AQI forecast (~6 days) for the nearest reporting
    /// area. Entries with `aqi == -1` carry no forecast value.
    func fetchForecast(lat: Double, lon: Double) async throws -> [AirNowForecastEntry] {
        let cacheKey = Self.cacheKey("airnow_forecast", lat, lon)
        if let cached = cache.object(forKey: cacheKey),
           !cached.isExpired(maxAge: cacheMaxAge),
           let forecasts = cached.forecasts {
            return forecasts
        }

        guard let url = URL(string: "\(baseURL)/forecast/current/?format=application/json&latitude=\(lat)&longitude=\(lon)&distance=25&API_KEY=\(apiKey)") else {
            throw URLError(.badURL)
        }

        let forecasts: [AirNowForecastEntry] = try await fetchJSON(from: url)
        cache.setObject(CachedAirNowData(observations: nil, forecasts: forecasts), forKey: cacheKey)
        return forecasts
    }

    // MARK: - Private helpers

    /// Cache keys round coordinates to ~1 km so jittering GPS fixes hit the
    /// same entry — AirNow resolves to a 25-mile reporting area anyway, and
    /// full-precision keys would make live-location callers miss on every
    /// refresh.
    private static func cacheKey(_ prefix: String, _ lat: Double, _ lon: Double) -> NSString {
        return String(format: "%@_%.2f_%.2f", prefix, lat, lon) as NSString
    }

    private func fetchJSON<T: Decodable>(from url: URL) async throws -> T {
        let (data, response) = try await urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            // Log the status: a bare -1011 hid the 2026 endpoint retirement (410).
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("⚠️ AirNow HTTP \(status) for \(url.path)")
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func loadConfig() {
        guard let path = Bundle.main.path(forResource: "AirNow", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            print("🚨 AirNowService: AirNow.plist not found or incorrectly formatted — AirNow disabled, OpenWeather fallback will be used.")
            config = nil
            return
        }
        config = dict
        if config?["AirNowApiKey"] == nil {
            print("🚨 AirNowService WARNING: AirNowApiKey missing in AirNow.plist!")
        }
    }
}

private final class CachedAirNowData {
    let observations: [AirNowObservation]?
    let forecasts: [AirNowForecastEntry]?
    let timestamp: Date

    init(observations: [AirNowObservation]?, forecasts: [AirNowForecastEntry]?) {
        self.observations = observations
        self.forecasts = forecasts
        self.timestamp = Date()
    }

    func isExpired(maxAge: TimeInterval) -> Bool {
        return Date().timeIntervalSince(timestamp) > maxAge
    }
}

// MARK: - Route window selection

/// Picks the official AQI for a planned ride window from AirNow data:
/// daily forecast entries for the window's calendar dates, plus current
/// observations when the ride starts within 3 hours (or is underway).
/// The worst (max) AQI wins, per EPA convention.
enum AirNowRouteAQISelector {

    static func select(
        observations: [AirNowObservation],
        forecasts: [AirNowForecastEntry],
        windowStart: Date,
        windowEnd: Date,
        now: Date = Date(),
        // Deliberate approximation: window dates use the device calendar,
        // while dateValid is the reporting area's local date. Rides are
        // planned near the user so these almost always agree; a distant-
        // timezone route at worst matches an adjacent day's daily forecast
        // or falls through to the OpenWeather fallback.
        calendar: Calendar = .current
    ) -> (aqi: Int, dominantPollutant: EPAAirQualityCalculator.Pollutant)? {
        let start = min(windowStart, windowEnd)
        let end = max(windowStart, windowEnd)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        // Seeding end's day is load-bearing: stepping from a late `start` in
        // whole days can overshoot an early-morning `end` (e.g. 22:00 → 02:00
        // overnight), so the loop alone would miss the final calendar day.
        var windowDayStrings: Set<String> = [formatter.string(from: end)]
        var cursor = start
        while cursor <= end {
            windowDayStrings.insert(formatter.string(from: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        var candidates: [(aqi: Int, parameterName: String)] = []

        for entry in forecasts where entry.aqi >= 0 {
            let day = entry.dateForecast.trimmingCharacters(in: .whitespacesAndNewlines)
            if windowDayStrings.contains(day) {
                candidates.append((entry.aqi, entry.parameterName))
            }
        }

        // Include live observations for rides starting soon (or underway):
        // NowCast reflects conditions the daily forecast may lag behind.
        if start <= now.addingTimeInterval(3 * 3600) {
            for observation in observations where observation.aqi >= 0 {
                candidates.append((observation.aqi, observation.parameterName))
            }
        }

        guard let worst = candidates.max(by: { $0.aqi < $1.aqi }) else { return nil }
        return (min(worst.aqi, 500), pollutant(from: worst.parameterName))
    }

    private static func pollutant(from name: String) -> EPAAirQualityCalculator.Pollutant {
        switch name.trimmingCharacters(in: .whitespaces).uppercased() {
        case "PM2.5": return .pm25
        case "PM10": return .pm10
        case "O3", "OZONE": return .ozone
        case "NO2": return .no2
        case "SO2": return .so2
        case "CO": return .co
        // Unknown parameters still count toward the AQI; the label (not
        // currently rendered) defaults to the most common driver.
        default: return .pm25
        }
    }
}
