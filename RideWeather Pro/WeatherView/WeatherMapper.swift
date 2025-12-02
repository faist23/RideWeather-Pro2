

//
//  WeatherMapper.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/16/25.
//

import Foundation

struct WeatherMapper {
    // In WeatherMapper.swift, replace your existing mapping functions with these
    
    static func mapCurrentToDisplayModel(_ current: CurrentWeatherResponse) -> DisplayWeatherModel {
        let temp = current.main.temp
        let humidity = Double(current.main.humidity)
        var finalFeelsLike = current.main.feelsLike
                
        return DisplayWeatherModel(
            temp: temp,
            feelsLike: finalFeelsLike,
            humidity: current.main.humidity,
            windSpeed: current.wind.speed,
            windDirection: current.wind.direction,
            windDeg: current.wind.deg,
            description: current.weather.first?.description.capitalized ?? "Clear",
            iconName: current.weather.first?.iconName ?? "sun.max.fill",
            pop: 0.0,
            visibility: current.visibility,
            uvIndex: nil
        )
    }
    
    static func mapForecastItemToDisplayModel(_ forecastItem: HourlyItem) -> DisplayWeatherModel {
        let temp = forecastItem.temp
        let humidity = Double(forecastItem.humidity)
        var finalFeelsLike = forecastItem.feelsLike
               
        return DisplayWeatherModel(
            temp: temp,
            feelsLike: finalFeelsLike,
            humidity: forecastItem.humidity,
            windSpeed: forecastItem.windSpeed,
            windDirection: mapWindDirection(degrees: Double(forecastItem.windDeg)),
            windDeg: forecastItem.windDeg,
            description: forecastItem.weather.first?.description.capitalized ?? "Clear",
            iconName: forecastItem.weather.first?.iconName ?? "sun.max.fill",
            pop: forecastItem.pop,
            visibility: nil,
            uvIndex: forecastItem.uvi
        )
    }
    
    // Enhanced mapper that includes complete weather data
    static func mapCurrentToDisplayModelWithEnhancements(_ current: CurrentWeatherResponse, insights: EnhancedWeatherInsights) -> DisplayWeatherModel {
        DisplayWeatherModel(
            temp: current.main.temp,
            feelsLike: current.main.feelsLike,
            humidity: current.main.humidity,
            windSpeed: current.wind.speed,
            windDirection: current.wind.direction,
            windDeg: current.wind.deg,
            description: current.weather.first?.description.capitalized ?? "Clear",
            iconName: current.weather.first?.iconName ?? "sun.max.fill",
            pop: 0.50,
            visibility: insights.visibility,
            uvIndex: insights.uvIndex
        )
    }
    
    // This now works because HourlyForecast has an init(from: HourlyItem)
    static func mapForecastItemToUIModel(_ item: HourlyItem) -> HourlyForecast {
        return HourlyForecast(from: item)
    }
    
    // This now works because HourlyForecast has an init(from: HourlyItem)
    static func mapHourlyItemToUIModel(_ item: HourlyItem) -> HourlyForecast {
        return HourlyForecast(from: item)
    }
    
    // MARK: - Daily Mapping

    static func mapDailyItem(_ item: DailyItem) -> DailyForecast {
        let date = Date(timeIntervalSince1970: item.dt)

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"   // e.g. "Mon"

        return DailyForecast(
            date: date,
            dayName: formatter.string(from: date),
            iconName: item.weather.first?.iconName ?? "cloud.fill",
            pop: item.pop,
            high: item.temp.max,
            low: item.temp.min,
            windSpeed: item.windSpeed,
            windDeg: item.windDeg
        )
    }

    // MARK: - Helpers

    static func mapIcon(from iconString: String) -> String {
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

    static func mapWindDirection(degrees: Double) -> String {
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE",
                    "S","SSW","SW","WSW","W","WNW","NW","NNW"]
        let normalizedDegrees = degrees.truncatingRemainder(dividingBy: 360)
        let index = Int((normalizedDegrees + 11.25) / 22.5) % 16
        return dirs[index]
    }
    
    private static func getWindDirection(degrees: Double) -> String {
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
        let index = Int((degrees+11.25)/22.5) % 16
        return dirs[index]
    }
    
    // NOAA Heat Index calculation (Steadman algorithm)
    private static func calculateHeatIndex(tempF: Double, humidity: Double) -> Double {
        // Simple check: Heat index doesn't apply below 80F
        guard tempF >= 80.0, humidity >= 40.0 else { return tempF }
        
        let T = tempF
        let R = humidity
        
        // Steadman's Regression Equation
        var hi = 0.5 * (T + 61.0 + ((T - 68.0) * 1.2) + (R * 0.094))
        
        // If the HI is >= 80F, use the full regression
        if hi >= 80.0 {
            let c1: Double = -42.379
            let c2: Double = 2.04901523
            let c3: Double = 10.14333127
            let c4: Double = -0.22475541
            let c5: Double = -6.83783e-3
            let c6: Double = -5.481717e-2
            let c7: Double = 1.22874e-3
            let c8: Double = 8.5282e-4
            let c9: Double = -1.99e-6
            
            let T2 = T * T
            let R2 = R * R
            
            hi = c1 + (c2 * T) + (c3 * R) + (c4 * T * R) + (c5 * T2) +
            (c6 * R2) + (c7 * T2 * R) + (c8 * T * R2) + (c9 * T2 * R2)
            
            // Adjustments for specific conditions
            if R < 13 && T >= 80.0 && T <= 112.0 {
                let adjustment = ((13.0 - R) / 4.0) * sqrt((17.0 - abs(T - 95.0)) / 17.0)
                hi -= adjustment
            } else if R > 85 && T >= 80.0 && T <= 87.0 {
                let adjustment = ((R - 85.0) / 10.0) * ((87.0 - T) / 5.0)
                hi += adjustment
            }
        }
        // Ensure calculated HI isn't lower than actual temp
        return max(hi, T)
    }
}
