//
//  WidgetDataFetcher.swift
//  RideWeatherComplications
//
//  Fetches fresh data for complications independently from the main app
//

import Foundation
import HealthKit

@MainActor
class WidgetDataFetcher {
    static let shared = WidgetDataFetcher()
    private let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")
    private let healthStore = HKHealthStore()
    
    private init() {}
    
    // MARK: - Fetch All Data
    
    func fetchAllData() async {
        // Run all fetches concurrently
        async let stepsTask = fetchTodaySteps()
        async let weatherTask = fetchWeather()
        
        let (steps, weather) = await (stepsTask, weatherTask)
        
        // Save to UserDefaults
        if let steps = steps {
            defaults?.set(steps, forKey: "widget_today_steps")
        }
        
        if let weatherData = weather {
            defaults?.set(weatherData, forKey: "widget_weather_summary")
        }
        
        print("🔄 Widget data refresh complete")
    }
    
    // MARK: - Fetch Steps from HealthKit
    
    private func fetchTodaySteps() async -> Int? {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("⚠️ HealthKit not available")
            return nil
        }
        
        let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        
        // Request authorization (will be instant if already authorized)
        let typesToRead: Set<HKObjectType> = [stepsType]
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
        } catch {
            print("❌ HealthKit authorization failed: \(error)")
            return nil
        }
        
        // Query today's steps
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: now,
            options: .strictStartDate
        )
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepsType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    print("❌ Steps query failed: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                let steps = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                print("✅ Fetched steps: \(Int(steps))")
                continuation.resume(returning: Int(steps))
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Fetch Weather from API
    
    private func fetchWeather() async -> Data? {
        // Get stored location (you should have this saved from the main app)
        guard let latitude = defaults?.double(forKey: "user_latitude"),
              let longitude = defaults?.double(forKey: "user_longitude"),
              latitude != 0, longitude != 0 else {
            print("⚠️ No location data available")
            return nil
        }
        
        // Use your weather API (replace with your actual API key and endpoint)
        let apiKey = "YOUR_WEATHER_API_KEY" // TODO: Replace with your API key
        let urlString = "https://api.openweathermap.org/data/2.5/weather?lat=\(latitude)&lon=\(longitude)&appid=\(apiKey)&units=imperial"
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid weather URL")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ Weather API returned error")
                return nil
            }
            
            // Parse and convert to your format
            if let weatherData = parseWeatherResponse(data) {
                print("✅ Fetched weather: \(weatherData.temperature)°F")
                return try? JSONEncoder().encode(weatherData)
            }
            
            return nil
        } catch {
            print("❌ Weather fetch failed: \(error)")
            return nil
        }
    }
    
    // MARK: - Parse Weather Response
    
    private func parseWeatherResponse(_ data: Data) -> SharedWeatherSummary? {
        struct OpenWeatherResponse: Codable {
            let main: Main
            let weather: [Weather]
            let wind: Wind
            
            struct Main: Codable {
                let temp: Double
                let feels_like: Double
            }
            
            struct Weather: Codable {
                let main: String
                let icon: String
            }
            
            struct Wind: Codable {
                let speed: Double
                let deg: Int
            }
        }
        
        do {
            let response = try JSONDecoder().decode(OpenWeatherResponse.self, from: data)
            
            // Map weather condition to SF Symbol
            let conditionIcon = mapWeatherIcon(response.weather.first?.main ?? "Clear")
            
            // Convert wind direction
            let windDirection = degreesToCardinal(response.wind.deg)
            
            return SharedWeatherSummary(
                temperature: Int(response.main.temp.rounded()),
                feelsLike: Int(response.main.feels_like.rounded()),
                conditionIcon: conditionIcon,
                windSpeed: Int(response.wind.speed.rounded()),
                windDirection: windDirection,
                pop: 0, // OpenWeather free tier doesn't include precipitation
                generatedAt: Date()
            )
        } catch {
            print("❌ Failed to parse weather: \(error)")
            return nil
        }
    }
    
    // MARK: - Helper Functions
    
    private func mapWeatherIcon(_ condition: String) -> String {
        switch condition.lowercased() {
        case "clear":
            return "sun.max.fill"
        case "clouds":
            return "cloud.fill"
        case "rain", "drizzle":
            return "cloud.rain.fill"
        case "thunderstorm":
            return "cloud.bolt.fill"
        case "snow":
            return "cloud.snow.fill"
        case "mist", "fog":
            return "cloud.fog.fill"
        default:
            return "cloud.fill"
        }
    }
    
    private func degreesToCardinal(_ degrees: Int) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((Double(degrees) + 22.5) / 45.0) % 8
        return directions[index]
    }
}

// Shared data structure (should match your complications file)
struct SharedWeatherSummary: Codable {
    let temperature: Int
    let feelsLike: Int
    let conditionIcon: String
    let windSpeed: Int
    let windDirection: String
    let pop: Int
    let generatedAt: Date
}