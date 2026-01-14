//
//  OpenWeatherAPIModels.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/12/25.
//

import Foundation
import CoreLocation
import SwiftUI

// MARK: - UI-Facing Models
struct DisplayWeatherModel {
    let temp: Double
    let feelsLike: Double
    let humidity: Int
    let windSpeed: Double
    let windDirection: String
    let windDeg: Int
    let description: String
    let iconName: String
    let pop: Double
    let visibility: Int? // Add visibility
    let uvIndex: Double? // Add UV index
}

struct HourlyForecast: Identifiable, Equatable {
    let id: UUID
    let time: String
    let date: Date
    let iconName: String
    let temp: Double
    let feelsLike: Double
    let pop: Double
    let humidity: Int
    let windSpeed: Double
    let windDeg: Int
    let uvIndex: Double?
    var aqi: Int? // mutable property for Air Quality Index

    var windDirection: String {
        switch windDeg {
        case 0...22, 338...360: return "N"
        case 23...67: return "NE"
        case 68...112: return "E"
        case 113...157: return "SE"
        case 158...202: return "S"
        case 203...247: return "SW"
        case 248...292: return "W"
        case 293...337: return "NW"
        default: return "N/A"
        }
    }

    static func == (lhs: HourlyForecast, rhs: HourlyForecast) -> Bool {
        return lhs.id == rhs.id &&
               lhs.time == rhs.time &&
               lhs.date == rhs.date &&
               lhs.iconName == rhs.iconName &&
               lhs.temp == rhs.temp &&
               lhs.feelsLike == rhs.feelsLike &&
               lhs.pop == rhs.pop &&
               lhs.humidity == rhs.humidity &&
               lhs.windSpeed == rhs.windSpeed &&
               lhs.windDeg == rhs.windDeg &&
               lhs.uvIndex == rhs.uvIndex &&
               lhs.aqi == rhs.aqi
    }

    private static func mapIcon(from iconString: String) -> String {
        switch iconString {
        case "01d": return "sun.max.fill"
        case "01n": return "moon.fill"
        case "02d": return "cloud.sun.fill"
        case "02n": return "cloud.moon.fill"
        case "03d", "03n": return "cloud.fill"
        case "04d", "04n": return "smoke.fill"
        case "09d", "09n": return "cloud.drizzle.fill"
        case "10d": return "cloud.sun.rain.fill"
        case "10n": return "cloud.moon.rain.fill"
        case "11d", "11n": return "cloud.bolt.fill"
        case "13d", "13n": return "snow"
        case "50d", "50n": return "cloud.fog.fill"
        default: return "questionmark.diamond.fill"
        }
    }

    // Initializer for the 6-hour forecast data (HourlyItem)
    init(from item: HourlyItem) {
        let itemDate = Date(timeIntervalSince1970: item.dt)
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"

        self.id = UUID()
        self.date = itemDate
        self.time = formatter.string(from: itemDate)
        self.iconName = item.weather.first?.iconName ?? "questionmark.diamond.fill"
        self.temp = item.temp
        self.feelsLike = item.feelsLike
        self.pop = item.pop
        self.humidity = item.humidity
        self.windSpeed = item.windSpeed
        self.windDeg = item.windDeg
        self.uvIndex = item.uvi // Map the UV index from the API item
        self.aqi = nil           // AQI will be populated later
    }

    // Initializer for the 48-hour forecast data (HourlyWeatherData)
    init(from data: HourlyWeatherData) {
        let itemDate = Date(timeIntervalSince1970: TimeInterval(data.dt))
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"

        self.id = UUID()
        self.date = itemDate
        self.time = formatter.string(from: itemDate)
        self.iconName = Self.mapIcon(from: data.weather.first?.icon ?? "")
        self.temp = data.temp
        self.feelsLike = data.feelsLike
        self.pop = data.pop
        self.humidity = data.humidity
        self.windSpeed = data.windSpeed
        self.windDeg = data.windDeg
        self.uvIndex = data.uvi // Map the UV index from the API data
        self.aqi = nil           // AQI will be populated later
    }
    
    // Initializer for creating sample/test data
    init(id: UUID = UUID(), time: String, date: Date, iconName: String, temp: Double, feelsLike: Double, pop: Double, windSpeed: Double, windDeg: Int, humidity: Int, uvIndex: Double? = nil, aqi: Int? = nil) {
        self.id = id
        self.time = time
        self.date = date
        self.iconName = iconName
        self.temp = temp
        self.feelsLike = feelsLike
        self.pop = pop
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.windDeg = windDeg
        self.uvIndex = uvIndex
        self.aqi = aqi    
    }
}

// MARK: - NEW Daily Forecast UI Model
struct DailyForecast: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let dayName: String
    let iconName: String

    let pop: Double
    let high: Double
    let low: Double

    let windSpeed: Double
    let windDeg: Int
    let summary: String
    
    var windDirection: String {
        WeatherMapper.mapWindDirection(degrees: Double(windDeg))
    }

    // Direction the wind is BLOWING TO (not from)
    var blowingDirection: String {
        let adjusted = Double((windDeg + 180) % 360)
        return WeatherMapper.mapWindDirection(degrees: adjusted)
    }
}


// MARK: - API Response Models
struct CurrentWeatherResponse: Codable {
    let coord: Coordinates
    let weather: [Weather]
    let main: MainDetails
    let wind: Wind
    let visibility: Int? // visibility in meters
    let name: String
}

struct OneCallResponse: Codable {
    let hourly: [HourlyItem]
    let alerts: [OWMAlert]?
}

// MARK: Alert API Model
struct OWMAlert: Codable {
    let sender_name: String
    let event: String
    let start: TimeInterval
    let end: TimeInterval
    let description: String
    let tags: [String]
}

// MARK: - NEW: Daily Forecast API Models
struct DailyResponse: Codable {
    let daily: [DailyItem]
}

struct HourlyItem: Codable {
    let dt: TimeInterval
    let temp: Double
    let feelsLike: Double
    let pop: Double
    let humidity: Int
    let weather: [Weather]
    let windSpeed: Double
    let windDeg: Int
    let uvi: Double 

    enum CodingKeys: String, CodingKey {
        case dt, temp, weather, pop, humidity, uvi
        case feelsLike = "feels_like"
        case windSpeed = "wind_speed"
        case windDeg = "wind_deg"
    }
    
    // Custom initializer to handle missing uvi
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        dt = try container.decode(TimeInterval.self, forKey: .dt)
        temp = try container.decode(Double.self, forKey: .temp)
        feelsLike = try container.decode(Double.self, forKey: .feelsLike)
        pop = try container.decode(Double.self, forKey: .pop)
        humidity = try container.decode(Int.self, forKey: .humidity)
        weather = try container.decode([Weather].self, forKey: .weather)
        windSpeed = try container.decode(Double.self, forKey: .windSpeed)
        windDeg = try container.decode(Int.self, forKey: .windDeg)
        
        // Provide default value if uvi is missing
        uvi = try container.decodeIfPresent(Double.self, forKey: .uvi) ?? 0.0
    }

    var windDirection: String {
        switch windDeg {
        case 0...22, 338...360: return "N"
        case 23...67: return "NE"
        case 68...112: return "E"
        case 113...157: return "SE"
        case 158...202: return "S"
        case 203...247: return "SW"
        case 248...292: return "W"
        case 293...337: return "NW"
        default: return "N/A"
        }
    }
}

struct DailyItem: Codable {
    let dt: TimeInterval
    let temp: DailyTemp
    let pop: Double
    let weather: [Weather]
    let windSpeed: Double
    let windDeg: Int
    let summary: String?
    
    enum CodingKeys: String, CodingKey {
        case dt, temp, pop, weather
        case windSpeed = "wind_speed"
        case windDeg = "wind_deg"
        case summary
    }
}


struct DailyTemp: Codable {
    let min: Double
    let max: Double
}

// MARK: - Shared API Model Components
struct Coordinates: Codable {
    let lon: Double
    let lat: Double
}

struct MainDetails: Codable {
    let temp: Double
    let feelsLike: Double
    let humidity: Int
    enum CodingKeys: String, CodingKey {
        case temp
        case feelsLike = "feels_like"
        case humidity
    }
}

struct Weather: Codable {
    let main: String
    let description: String
    let icon: String
    
    var iconName: String {
        switch icon {
        case "01d": return "sun.max.fill"
        case "01n": return "moon.fill"
        case "02d": return "cloud.sun.fill"
        case "02n": return "cloud.moon.fill"
        case "03d", "03n": return "cloud.fill"
        case "04d", "04n": return "smoke.fill"
        case "09d", "09n": return "cloud.drizzle.fill"
        case "10d": return "cloud.sun.rain.fill"
        case "10n": return "cloud.moon.rain.fill"
        case "11d", "11n": return "cloud.bolt.fill"
        case "13d", "13n": return "snow"
        case "50d", "50n": return "cloud.fog.fill"
        default: return "questionmark.diamond.fill"
        }
    }
}

struct Wind: Codable {
    let speed: Double
    let deg: Int
    
    var direction: String {
        switch deg {
        case 0...22, 338...360: return "N"
        case 23...67: return "NE"
        case 68...112: return "E"
        case 113...157: return "SE"
        case 158...202: return "S"
        case 203...247: return "SW"
        case 248...292: return "W"
        case 293...337: return "NW"
        default: return "N/A"
        }
    }
}

struct RouteWeatherPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let distance: Double
    let eta: Date
    let weather: DisplayWeatherModel
}

extension RouteWeatherPoint: Codable {
    enum CodingKeys: String, CodingKey {
        case coordinate_latitude, coordinate_longitude
        case distance, eta
        case weather_temp, weather_feelsLike, weather_humidity
        case weather_windSpeed, weather_windDirection, weather_windDeg
        case weather_description, weather_iconName, weather_pop
        case weather_visibility, weather_uvIndex
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coordinate.latitude, forKey: .coordinate_latitude)
        try container.encode(coordinate.longitude, forKey: .coordinate_longitude)
        try container.encode(distance, forKey: .distance)
        try container.encode(eta, forKey: .eta)
        try container.encode(weather.temp, forKey: .weather_temp)
        try container.encode(weather.feelsLike, forKey: .weather_feelsLike)
        try container.encode(weather.humidity, forKey: .weather_humidity)
        try container.encode(weather.windSpeed, forKey: .weather_windSpeed)
        try container.encode(weather.windDirection, forKey: .weather_windDirection)
        try container.encode(weather.windDeg, forKey: .weather_windDeg)
        try container.encode(weather.description, forKey: .weather_description)
        try container.encode(weather.iconName, forKey: .weather_iconName)
        try container.encode(weather.pop, forKey: .weather_pop)
        try container.encodeIfPresent(weather.visibility, forKey: .weather_visibility)
        try container.encodeIfPresent(weather.uvIndex, forKey: .weather_uvIndex)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .coordinate_latitude)
        let longitude = try container.decode(Double.self, forKey: .coordinate_longitude)
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        distance = try container.decode(Double.self, forKey: .distance)
        eta = try container.decode(Date.self, forKey: .eta)
        
        weather = DisplayWeatherModel(
            temp: try container.decode(Double.self, forKey: .weather_temp),
            feelsLike: try container.decode(Double.self, forKey: .weather_feelsLike),
            humidity: try container.decode(Int.self, forKey: .weather_humidity),
            windSpeed: try container.decode(Double.self, forKey: .weather_windSpeed),
            windDirection: try container.decode(String.self, forKey: .weather_windDirection),
            windDeg: try container.decode(Int.self, forKey: .weather_windDeg),
            description: try container.decode(String.self, forKey: .weather_description),
            iconName: try container.decode(String.self, forKey: .weather_iconName),
            pop: try container.decode(Double.self, forKey: .weather_pop),
            visibility: try container.decodeIfPresent(Int.self, forKey: .weather_visibility),
            uvIndex: try container.decodeIfPresent(Double.self, forKey: .weather_uvIndex)
        )
    }
}

// MARK: - Air Pollution API Models
struct AirPollutionResponse: Codable {
    let coord: Coordinates
    let list: [AirPollutionData]
}

struct AirPollutionData: Codable {
    let dt: TimeInterval
    let main: AirQualityIndex
    let components: PollutionComponents
}

struct AirQualityIndex: Codable {
    let aqi: Int // Air Quality Index (1-5 scale)
}

struct PollutionComponents: Codable {
    let co: Double      // Carbon monoxide (μg/m³)
    let no: Double      // Nitrogen monoxide (μg/m³)
    let no2: Double     // Nitrogen dioxide (μg/m³)
    let o3: Double      // Ozone (μg/m³)
    let so2: Double     // Sulphur dioxide (μg/m³)
    let pm2_5: Double   // Fine particles matter (μg/m³)
    let pm10: Double    // Coarse particulate matter (μg/m³)
    let nh3: Double     // Ammonia (μg/m³)
}

// MARK: - Enhanced Display Models
struct EnhancedWeatherInsights {
    let uvIndex: Double
    let uvLevel: String
    let visibility: Int // meters
    let visibilityLevel: String
    let airQuality: Int // 1-5 scale
    let airQualityLevel: String
    let airQualityColor: Color
    
    var uvColor: Color {
        switch uvIndex {
        case 0..<3: return .green
        case 3..<6: return .yellow
        case 6..<8: return .orange
        case 8..<11: return .red
        default: return .purple
        }
    }
    
    var visibilityColor: Color {
        switch visibility {
        case 10000...: return .green
        case 5000..<10000: return .yellow
        case 1000..<5000: return .orange
        default: return .red
        }
    }
    
    init(uvIndex: Double, visibility: Int, airQuality: Int) {
        self.uvIndex = uvIndex
        self.visibility = visibility
        self.airQuality = airQuality
        
        // UV Level mapping
        switch uvIndex {
        case 0..<3: self.uvLevel = "Low"
        case 3..<6: self.uvLevel = "Moderate"
        case 6..<8: self.uvLevel = "High"
        case 8..<11: self.uvLevel = "Very High"
        default: self.uvLevel = "Extreme"
        }
        
        // Visibility level mapping (convert meters to miles/km)
        switch visibility {
        case 10000...: self.visibilityLevel = "Excellent"
        case 5000..<10000: self.visibilityLevel = "Good"
        case 1000..<5000: self.visibilityLevel = "Moderate"
        default: self.visibilityLevel = "Poor"
        }
        
        // Air Quality mapping (WHO scale)
        switch airQuality {
        case 1:
            self.airQualityLevel = "Good"
            self.airQualityColor = .green
        case 2:
            self.airQualityLevel = "Fair"
            self.airQualityColor = .yellow
        case 3:
            self.airQualityLevel = "Moderate"
            self.airQualityColor = .orange
        case 4:
            self.airQualityLevel = "Poor"
            self.airQualityColor = .red
        case 5:
            self.airQualityLevel = "Very Poor"
            self.airQualityColor = .purple
        default:
            self.airQualityLevel = "Unknown"
            self.airQualityColor = .gray
        }
    }
}

