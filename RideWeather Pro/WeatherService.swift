//
//  WeatherService.swift
//  RideWeather Pro
//
//  Enhanced with extended hourly data support
//

import Foundation
import Combine

class WeatherService {
    // MARK: - Configuration (Secrets Management)
    private var openWeather: [String: String]?
    
    private var apiKey: String {
        // Safely access config, provide a non-functional default if missing
        return configValue(forKey: "OpenWeatherApiKey") ?? "INVALID_API"
    }
    private let baseWeatherURL = "https://api.openweathermap.org/data/2.5"
    private let baseOneCallURL = "https://api.openweathermap.org/data/3.0"
    // MARK: - Additional Properties (add to your WeatherService class)
    private let airPollutionCache = NSCache<NSString, CachedAirPollutionData>()
    
    // Caching
    private let cache = NSCache<NSString, CachedWeatherData>()
    private let cacheQueue = DispatchQueue(label: "weather.cache", qos: .utility)
    
    // URL Session with optimized configuration
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024)
        return URLSession(configuration: config)
    }()
    
    init() {
        loadConfig()
        cache.countLimit = 100 // Limit cache size
        cache.totalCostLimit = 10 * 1024 * 1024 // 10MB
    }
    
    func fetchCurrentWeather(lat: Double, lon: Double, units: String) async throws -> CurrentWeatherResponse {
        let cacheKey = "current_\(lat)_\(lon)_\(units)"
        
        // Check cache first
        if let cachedData = await getCachedData(key: cacheKey),
           !cachedData.isExpired(maxAge: 300) { // 5 minutes for current weather
            return cachedData.currentWeather!
        }
        
        guard let url = URL(string: "\(baseWeatherURL)/weather?lat=\(lat)&lon=\(lon)&appid=\(apiKey)&units=\(units)") else {
            throw URLError(.badURL)
        }
        
        let response: CurrentWeatherResponse = try await fetchData(from: url)
        
        // Cache the result
        await cacheData(key: cacheKey, currentWeather: response, forecast: nil, extendedForecast: nil)
        
        return response
    }
    
    // Regular forecast for 6-hour display (excludes hourly to save bandwidth)
    func fetchForecast(lat: Double, lon: Double, units: String) async throws -> OneCallResponse {
        let cacheKey = "forecast_\(lat)_\(lon)_\(units)"
        
        // Check cache first
        if let cachedData = await getCachedData(key: cacheKey),
           !cachedData.isExpired(maxAge: 900) { // 15 minutes for forecast
            return cachedData.forecast!
        }
        
        // For regular forecast, exclude hourly data to save bandwidth
        let exclude = "current,minutely,daily"
        guard let url = URL(string: "\(baseOneCallURL)/onecall?lat=\(lat)&lon=\(lon)&exclude=\(exclude)&appid=\(apiKey)&units=\(units)") else {
            throw URLError(.badURL)
        }
        
        let response: OneCallResponse = try await fetchData(from: url)
        
        // Cache the result
        await cacheData(key: cacheKey, currentWeather: nil, forecast: response, extendedForecast: nil)
        
        return response
    }
    
    // separate daily forecast call 
    func fetchDailyForecast(lat: Double, lon: Double, units: String) async throws -> [DailyItem] {
        let cacheKey = "daily_\(lat)_\(lon)_\(units)"
        if let cached = await getCachedData(key: cacheKey), !cached.isExpired(maxAge: 1800) {
            if let extended = cached.extendedForecast {
                // If we used extendedForecast to store hourly-only earlier, ignore; here we expect daily stored in CachedWeatherData.forecastDaily
            }
            // Check for a place to store daily in our cache object — use forecast if it contains daily? To keep things simple we cache daily in a dedicated cache object keyed above.
        }
        
        // Exclude hourly + current + minutely + alerts to get only daily
        let exclude = "hourly,current,minutely,alerts"
        guard let url = URL(string: "\(baseOneCallURL)/onecall?lat=\(lat)&lon=\(lon)&exclude=\(exclude)&appid=\(apiKey)&units=\(units)") else {
            throw URLError(.badURL)
        }
        
        // Use a lightweight decoding into DailyResponse
        let (data, response) = try await urlSession.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeatherServiceError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200: break
        case 401: throw WeatherServiceError.invalidAPIKey
        case 429: throw WeatherServiceError.rateLimited
        case 404: throw WeatherServiceError.locationNotFound
        default: throw WeatherServiceError.serverError(httpResponse.statusCode)
        }
        
        do {
            let decoder = JSONDecoder()
            let dailyResp = try decoder.decode(DailyResponse.self, from: data)
            // Cache the daily response as a simple JSON blob via our existing cache wrapper
            // We'll store it in the forecast field wrapped inside a minimal OneCallResponse with empty hourly (not ideal but keeps cache types)
            // Instead, create a CachedWeatherData with extendedForecast nil and forecast nil but store the daily list inside a separate cache keyed by cacheKey
            let cachedDaily = DailyCacheWrapper(daily: dailyResp.daily, timestamp: Date())
            await withCheckedContinuation { cont in
                cacheQueue.async {
                    self.dailyCache.setObject(cachedDaily, forKey: NSString(string: cacheKey))
                    cont.resume()
                }
            }
            return dailyResp.daily
        } catch {
            throw WeatherServiceError.decodingError(error)
        }
    }
    
    // Extended forecast for analytics dashboard (includes 48 hours of hourly data)
    func fetchExtendedForecast(lat: Double, lon: Double, units: String) async throws -> ExtendedOneCallResponse {
        let cacheKey = "extended_forecast_\(lat)_\(lon)_\(units)"
        
        // Check cache first - longer cache time since this is expensive
        if let cachedData = await getCachedData(key: cacheKey),
           !cachedData.isExpired(maxAge: 1800) { // 30 minutes for extended forecast
            return cachedData.extendedForecast!
        }
        
        // Include hourly data but exclude everything else to optimize
        let exclude = "current,minutely,alerts"
        guard let url = URL(string: "\(baseOneCallURL)/onecall?lat=\(lat)&lon=\(lon)&exclude=\(exclude)&appid=\(apiKey)&units=\(units)") else {
            throw URLError(.badURL)
        }
        
        let response: ExtendedOneCallResponse = try await fetchData(from: url)
        
        // Cache the result
        await cacheData(key: cacheKey, currentWeather: nil, forecast: nil, extendedForecast: response)
        
        return response
    }
    
    func fetchAirPollution(lat: Double, lon: Double) async throws -> AirPollutionResponse {
        let cacheKey = "air_pollution_\(lat)_\(lon)"
        
        // Check cache first
        if let cachedData = await getCachedAirPollution(key: cacheKey),
           !cachedData.isExpired(maxAge: 3600) { // 1 hour cache
            return cachedData.airPollution
        }
        
        guard let url = URL(string: "\(baseWeatherURL)/air_pollution?lat=\(lat)&lon=\(lon)&appid=\(apiKey)") else {
            throw URLError(.badURL)
        }
        
        let response: AirPollutionResponse = try await fetchData(from: url)
        
        // Cache the result
        await cacheAirPollution(key: cacheKey, airPollution: response)
        
        return response
    }
    
    
    // Batch fetch for route weather points (more efficient)
    func fetchWeatherForPoints(_ points: [(lat: Double, lon: Double, units: String)]) async throws -> [OneCallResponse] {
        let maxConcurrentRequests = 5
        var results: [OneCallResponse] = []
        
        // Process in batches to avoid overwhelming the API
        for batch in points.chunked(into: maxConcurrentRequests) {
            let batchResults = try await withThrowingTaskGroup(of: OneCallResponse.self) { group in
                var batchResults: [OneCallResponse] = []
                
                for point in batch {
                    group.addTask {
                        return try await self.fetchForecast(lat: point.lat, lon: point.lon, units: point.units)
                    }
                }
                
                for try await result in group {
                    batchResults.append(result)
                }
                
                return batchResults
            }
            
            results.append(contentsOf: batchResults)
            
            // Small delay between batches to be respectful to the API
            if batch.count == maxConcurrentRequests {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }
        
        return results
    }
    
    private func fetchData<T: Decodable>(from url: URL) async throws -> T {
        let request = createRequest(for: url)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeatherServiceError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw WeatherServiceError.invalidAPIKey
        case 429:
            throw WeatherServiceError.rateLimited
        case 404:
            throw WeatherServiceError.locationNotFound
        default:
            throw WeatherServiceError.serverError(httpResponse.statusCode)
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw WeatherServiceError.decodingError(error)
        }
    }
    
    private func createRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("RideWeatherPro/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }
    
    // MARK: - Caching Methods
    
    private func getCachedData(key: String) async -> CachedWeatherData? {
        return await withCheckedContinuation { continuation in
            cacheQueue.async {
                let cachedData = self.cache.object(forKey: NSString(string: key))
                continuation.resume(returning: cachedData)
            }
        }
    }
    
    private func cacheData(key: String, currentWeather: CurrentWeatherResponse?, forecast: OneCallResponse?, extendedForecast: ExtendedOneCallResponse?) async {
        let cachedData = CachedWeatherData(
            currentWeather: currentWeather,
            forecast: forecast,
            extendedForecast: extendedForecast,
            timestamp: Date()
        )
        
        await withCheckedContinuation { continuation in
            cacheQueue.async {
                self.cache.setObject(cachedData, forKey: NSString(string: key))
                continuation.resume()
            }
        }
    }
    
    // Separate daily cache (wrapper)
    private let dailyCache = NSCache<NSString, DailyCacheWrapper>()
    
    private func getCachedDaily(key: String) async -> DailyCacheWrapper? {
        return await withCheckedContinuation { cont in
            cacheQueue.async {
                cont.resume(returning: self.dailyCache.object(forKey: NSString(string: key)))
            }
        }
    }
    
    // Clear expired cache entries periodically
    func cleanupCache() {
        cacheQueue.async {
            // Note: NSCache doesn't provide enumeration, so we rely on its automatic cleanup
            // For more sophisticated cleanup, you might want to use a custom cache implementation
        }
    }
    // MARK: - Air Pollution Cache Methods
    private func getCachedAirPollution(key: String) async -> CachedAirPollutionData? {
        return await withCheckedContinuation { continuation in
            cacheQueue.async {
                let cachedData = self.airPollutionCache.object(forKey: NSString(string: key))
                continuation.resume(returning: cachedData)
            }
        }
    }
    
    private func cacheAirPollution(key: String, airPollution: AirPollutionResponse) async {
        let cachedData = CachedAirPollutionData(
            airPollution: airPollution,  // Now non-optional
            timestamp: Date()
        )
        
        await withCheckedContinuation { continuation in
            cacheQueue.async {
                self.airPollutionCache.setObject(cachedData, forKey: NSString(string: key))
                continuation.resume()
            }
        }
    }
    
    private func loadConfig() {
        guard let path = Bundle.main.path(forResource: "OpenWeather", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            print("🚨 WeatherService FATAL ERROR: OpenWeather.plist not found or incorrectly formatted!")
            let errorMessage = "Critical configuration error. Weather integration disabled."
            openWeather = nil
            return
        }
        
        openWeather = dict
        print("WeatherService: Configuration loaded successfully.")
        
        if configValue(forKey: "OpenWeatherApiKey") == nil {
            print("🚨 WeatherService WARNING: OpenWeatherApiKey missing in OpenWeather.plist!")
        }
    }
    
    /// Helper to safely access config values
    private func configValue(forKey key: String) -> String? {
        return openWeather?[key]
    }
    
}

// MARK: - Complete Weather Data Structure
struct CompleteWeatherData {
    let current: CurrentWeatherResponse
    let forecast: OneCallResponse
    let airPollution: AirPollutionResponse
    
    var enhancedInsights: EnhancedWeatherInsights {
        // Extract UV from forecast if available
        let uvIndex = forecast.hourly.first?.uvi ?? 0.0
        
        // Extract visibility from current weather
        let visibility = current.visibility ?? 10000 // Default 10km if not available
        
        // Extract air quality
        let airQuality = airPollution.list.first?.main.aqi ?? 1
        
        return EnhancedWeatherInsights(
            uvIndex: uvIndex,
            visibility: visibility,
            airQuality: airQuality
        )
    }
}


// MARK: - Cache Data Structure

private class CachedWeatherData: NSObject {
    let currentWeather: CurrentWeatherResponse?
    let forecast: OneCallResponse?
    let extendedForecast: ExtendedOneCallResponse?
    let timestamp: Date
    
    init(currentWeather: CurrentWeatherResponse?, forecast: OneCallResponse?, extendedForecast: ExtendedOneCallResponse?, timestamp: Date) {
        self.currentWeather = currentWeather
        self.forecast = forecast
        self.extendedForecast = extendedForecast
        self.timestamp = timestamp
    }
    
    func isExpired(maxAge: TimeInterval) -> Bool {
        return Date().timeIntervalSince(timestamp) > maxAge
    }
}

// MARK: - Extended One Call Response Model

struct ExtendedOneCallResponse: Codable {
    let lat: Double
    let lon: Double
    let timezone: String
    let timezoneOffset: Int
    let hourly: [HourlyWeatherData] // This is the key - up to 48 hours of data
    
    enum CodingKeys: String, CodingKey {
        case lat, lon, timezone, hourly
        case timezoneOffset = "timezone_offset"
    }
}

struct HourlyWeatherData: Codable {
    let dt: Int
    let temp: Double
    let feelsLike: Double
    let pressure: Int
    let humidity: Int
    let dewPoint: Double
    let uvi: Double
    let clouds: Int
    let visibility: Int?
    let windSpeed: Double
    let windDeg: Int
    let windGust: Double?
    let weather: [WeatherCondition]
    let pop: Double // Probability of precipitation
    
    enum CodingKeys: String, CodingKey {
        case dt, temp, pressure, humidity, clouds, visibility, weather, pop
        case feelsLike = "feels_like"
        case dewPoint = "dew_point"
        case uvi
        case windSpeed = "wind_speed"
        case windDeg = "wind_deg"
        case windGust = "wind_gust"
    }
}

struct WeatherCondition: Codable {
    let id: Int
    let main: String
    let description: String
    let icon: String
}

// MARK: - Error Types

enum WeatherServiceError: LocalizedError {
    case invalidResponse
    case invalidAPIKey
    case rateLimited
    case locationNotFound
    case serverError(Int)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from weather service"
        case .invalidAPIKey:
            return "Invalid API key"
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .locationNotFound:
            return "Location not found"
        case .serverError(let code):
            return "Server error: \(code)"
        case .decodingError(let error):
            return "Data parsing error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Array Extension for Batching

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Air Pollution Cache Data
private class CachedAirPollutionData: NSObject {
    let airPollution: AirPollutionResponse  // Remove the optional - it should always have a value when cached
    let timestamp: Date
    
    init(airPollution: AirPollutionResponse, timestamp: Date) {
        self.airPollution = airPollution
        self.timestamp = timestamp
    }
    
    func isExpired(maxAge: TimeInterval) -> Bool {
        return Date().timeIntervalSince(timestamp) > maxAge
    }
}

// Wrapper for daily cache
private class DailyCacheWrapper: NSObject {
    let daily: [DailyItem]
    let timestamp: Date
    
    init(daily: [DailyItem], timestamp: Date) {
        self.daily = daily
        self.timestamp = timestamp
    }
    
    func isExpired(maxAge: TimeInterval) -> Bool {
        return Date().timeIntervalSince(timestamp) > maxAge
    }
}
