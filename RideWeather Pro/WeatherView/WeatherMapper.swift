
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
        // The API provides temperature in the user's selected units (F or C)
        let temp = current.main.temp
        let humidity = Double(current.main.humidity)
        var feelsLike = current.main.feelsLike

        // Threshold for heat index calculation (80°F or ~26.7°C)
        let tempThreshold = 26.7
        
        // Check if temp is in Fahrenheit or convert Celsius for the formula
        let tempInF = temp > 40 ? temp : (temp * 9/5) + 32
        
        if tempInF > 80.0 {
            let calculatedHeatIndexF = calculateHeatIndex(tempF: tempInF, humidity: humidity)
            // Convert back to Celsius if the original unit was Celsius
            let calculatedHeatIndex = temp > 40 ? calculatedHeatIndexF : (calculatedHeatIndexF - 32) * 5/9
            feelsLike = calculatedHeatIndex
        }

        return DisplayWeatherModel(
            temp: current.main.temp,
            feelsLike: feelsLike, // Use our new calculated value
            humidity: current.main.humidity,
            windSpeed: current.wind.speed,
            windDirection: current.wind.direction,
            windDeg: current.wind.deg,
            description: current.weather.first?.description.capitalized ?? "Clear",
            iconName: current.weather.first?.iconName ?? "sun.max.fill",
            pop: 0.50,
            visibility: current.visibility,
            uvIndex: nil
       )
    }

    static func mapForecastItemToDisplayModel(_ forecastItem: HourlyItem) -> DisplayWeatherModel {
        let temp = forecastItem.temp
        let humidity = Double(forecastItem.humidity)
        var feelsLike = forecastItem.feelsLike

        let tempThreshold = 26.7
        let tempInF = temp > 40 ? temp : (temp * 9/5) + 32
        
        if tempInF > 80.0 {
            let calculatedHeatIndexF = calculateHeatIndex(tempF: tempInF, humidity: humidity)
            let calculatedHeatIndex = temp > 40 ? calculatedHeatIndexF : (calculatedHeatIndexF - 32) * 5/9
            feelsLike = calculatedHeatIndex
        }
        
        return DisplayWeatherModel(
            temp: forecastItem.temp,
            feelsLike: feelsLike, // Use our new calculated value
            humidity: forecastItem.humidity,
            windSpeed: forecastItem.windSpeed,
            windDirection: forecastItem.windDirection,
            windDeg: forecastItem.windDeg,
            description: forecastItem.weather.first?.description.capitalized ?? "Clear",
            iconName: forecastItem.weather.first?.iconName ?? "sun.max.fill",
            pop: forecastItem.pop,
            visibility: nil,
            uvIndex: forecastItem.uvi
        )
    }

    /*static func mapCurrentToDisplayModel(_ current: CurrentWeatherResponse) -> DisplayWeatherModel {
        DisplayWeatherModel(
            temp: current.main.temp,
            feelsLike: current.main.feelsLike,
            humidity: current.main.humidity,
            windSpeed: current.wind.speed,
            windDirection: current.wind.direction,
            windDeg: current.wind.deg,
            description: current.weather.first?.description.capitalized ?? "Clear",
            iconName: current.weather.first?.iconName ?? "sun.max.fill",
            pop: 0.50, // Default value for current weather
            visibility: current.visibility, // Use visibility from current weather (can be nil)
            uvIndex: nil // Current weather doesn't have UV index, set to nil
        )
    }
    
    static func mapForecastItemToDisplayModel(_ forecastItem: HourlyItem) -> DisplayWeatherModel {
        DisplayWeatherModel(
            temp: forecastItem.temp,
            feelsLike: forecastItem.feelsLike,
            humidity: forecastItem.humidity,
            windSpeed: forecastItem.windSpeed,
            windDirection: forecastItem.windDirection,
            windDeg: forecastItem.windDeg,
            description: forecastItem.weather.first?.description.capitalized ?? "Clear",
            iconName: forecastItem.weather.first?.iconName ?? "sun.max.fill",
            pop: forecastItem.pop,
            visibility: nil, // HourlyItem doesn't have visibility, set to nil
            uvIndex: forecastItem.uvi // Use UV index from forecast (HourlyItem has this)
        )
    }*/
    
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
    
    static func mapWindDirection(degrees: Double) -> String {
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE",
                    "S","SSW","SW","WSW","W","WNW","NW","NNW"]
        let index = Int((degrees+11.25)/22.5) % 16
        return dirs[index]
    }
    
    private static func getWindDirection(degrees: Double) -> String {
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
        let index = Int((degrees+11.25)/22.5) % 16
        return dirs[index]
    }

    private static func calculateHeatIndex(tempF: Double, humidity: Double) -> Double {
        // NOAA heat index formula (Steadman algorithm)
        let c1: Double = -42.379
        let c2: Double = 2.04901523
        let c3: Double = 10.14333127
        let c4: Double = -0.22475541
        let c5: Double = -6.83783e-3
        let c6: Double = -5.481717e-2
        let c7: Double = 1.22874e-3
        let c8: Double = 8.5282e-4
        let c9: Double = -1.99e-6

        let T = tempF
        let R = humidity

        let heatIndex = c1 + (c2 * T) + (c3 * R) + (c4 * T * R) + (c5 * T * T) +
                        (c6 * R * R) + (c7 * T * T * R) + (c8 * T * R * R) +
                        (c9 * T * T * R * R)

        return heatIndex
    }
}
