//
//  WeatherMapper.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/16/25.
//

import Foundation
import WeatherKit
import CoreLocation

struct WeatherMapper {
    // MARK: - Apple WeatherKit Mappings
    
    @available(iOS 16.0, *)
    static func mapAppleCurrentToOpenWeather(_ current: WeatherKit.CurrentWeather, location: CLLocation, units: String, nextHourSummary: String?, minuteForecast: Forecast<MinuteWeather>?, upcomingSummary: String? = nil) -> CurrentWeatherResponse {
        let isImperial = units == "imperial"
        
        let temp = isImperial ? current.temperature.converted(to: .fahrenheit).value : current.temperature.converted(to: .celsius).value
        let feelsLike = isImperial ? current.apparentTemperature.converted(to: .fahrenheit).value : current.apparentTemperature.converted(to: .celsius).value
        let windSpeed = isImperial ? current.wind.speed.converted(to: .milesPerHour).value : current.wind.speed.converted(to: .kilometersPerHour).value
        
        let precipitationData = minuteForecast?.map { minute in
            PrecipitationPoint(date: minute.date, intensity: minute.precipitationIntensity.value)
        }
        
        return CurrentWeatherResponse(
            coord: Coordinates(lon: location.coordinate.longitude, lat: location.coordinate.latitude),
            weather: [Weather(main: current.condition.description, description: current.condition.description, icon: mapAppleConditionToIcon(current.condition))],
            main: MainDetails(temp: temp, feelsLike: feelsLike, humidity: Int(current.humidity * 100)),
            wind: Wind(speed: windSpeed, deg: Int(current.wind.direction.value)),
            visibility: Int(current.visibility.converted(to: .meters).value),
            name: "", // Keep empty, WeatherViewModel handles name via CityNameResolver
            nextHourSummary: nextHourSummary,
            precipitationData: precipitationData,
            upcomingConditionsSummary: upcomingSummary
        )
    }
    
    @available(iOS 16.0, *)
    static func mapAppleHourlyToOpenWeather(_ hour: WeatherKit.HourWeather) -> HourlyItem {
        return HourlyItem(
            dt: hour.date.timeIntervalSince1970,
            temp: hour.temperature.converted(to: .fahrenheit).value, 
            feelsLike: hour.apparentTemperature.converted(to: .fahrenheit).value,
            pop: hour.precipitationChance,
            humidity: Int(hour.humidity * 100),
            weather: [Weather(main: hour.condition.description, description: hour.condition.description, icon: mapAppleConditionToIcon(hour.condition))],
            windSpeed: hour.wind.speed.converted(to: .milesPerHour).value,
            windDeg: Int(hour.wind.direction.value),
            uvi: Double(hour.uvIndex.value)
        )
    }

    @available(iOS 16.0, *)
    static func mapAppleDailyToOpenWeather(_ day: WeatherKit.DayWeather) -> DailyItem {
        let condition = day.condition.description
        let precip = Int(day.precipitationChance * 100)
        let high = Int(day.highTemperature.converted(to: .fahrenheit).value)
        let low = Int(day.lowTemperature.converted(to: .fahrenheit).value)
        
        // Synthesize a more descriptive summary like OpenWeather's OneCall
        let detailSummary = "\(condition). High \(high)°, low \(low)°. \(precip)% chance of precipitation."
        
        return DailyItem(
            dt: day.date.timeIntervalSince1970,
            temp: DailyTemp(
                min: day.lowTemperature.converted(to: .fahrenheit).value,
                max: day.highTemperature.converted(to: .fahrenheit).value
            ),
            pop: day.precipitationChance,
            weather: [Weather(main: day.condition.description, description: day.condition.description, icon: mapAppleConditionToIcon(day.condition))],
            windSpeed: day.wind.speed.converted(to: .milesPerHour).value,
            windDeg: Int(hourToDeg(day.wind.direction)),
            summary: detailSummary
        )
    }

    @available(iOS 16.0, *)
    static func mapAppleHourlyToUIModel(_ hour: WeatherKit.HourWeather) -> HourlyForecast {
        return HourlyForecast(
            id: UUID(),
            time: hour.date.formatted(.dateTime.hour()),
            date: hour.date,
            iconName: mapAppleConditionToIcon(hour.condition),
            temp: hour.temperature.converted(to: .fahrenheit).value,
            feelsLike: hour.apparentTemperature.converted(to: .fahrenheit).value,
            pop: hour.precipitationChance,
            windSpeed: hour.wind.speed.converted(to: .milesPerHour).value,
            windDeg: Int(hourToDeg(hour.wind.direction)),
            humidity: Int(hour.humidity * 100),
            uvIndex: Double(hour.uvIndex.value),
            aqi: nil
        )
    }

    @available(iOS 16.0, *)
    private static func hourToDeg(_ direction: Measurement<UnitAngle>) -> Double {
        return direction.converted(to: .degrees).value
    }

    @available(iOS 16.0, *)
    static func mapAppleConditionToIcon(_ condition: WeatherKit.WeatherCondition) -> String {
        switch condition {
        case .clear, .mostlyClear: return "01d"
        case .partlyCloudy: return "02d"
        case .mostlyCloudy, .cloudy: return "03d"
        case .haze, .foggy, .blowingDust: return "50d"
        case .windy: return "03d" // No direct OWM wind icon
        case .drizzle, .heavyRain, .rain, .sunShowers: return "10d"
        case .flurries, .snow, .heavySnow, .sunFlurries: return "13d"
        case .thunderstorms: return "11d"
        default: return "03d"
        }
    }

    // Existing methods (rest unchanged)
    static func mapCurrentToDisplayModel(_ current: CurrentWeatherResponse) -> DisplayWeatherModel {
        return DisplayWeatherModel(
            temp: current.main.temp,
            feelsLike: current.main.feelsLike,
            humidity: current.main.humidity,
            windSpeed: current.wind.speed,
            windDirection: current.wind.direction,
            windDeg: current.wind.deg,
            description: current.weather.first?.description.capitalized ?? "Clear",
            iconName: current.weather.first?.iconName ?? "sun.max.fill",
            pop: 0.0,
            visibility: current.visibility,
            uvIndex: nil,
            nextHourSummary: current.nextHourSummary,
            precipitationData: current.precipitationData,
            upcomingConditionsSummary: current.upcomingConditionsSummary
        )
    }
    
    static func mapForecastItemToDisplayModel(_ forecastItem: HourlyItem) -> DisplayWeatherModel {
        return DisplayWeatherModel(
            temp: forecastItem.temp,
            feelsLike: forecastItem.feelsLike,
            humidity: forecastItem.humidity,
            windSpeed: forecastItem.windSpeed,
            windDirection: mapWindDirection(degrees: Double(forecastItem.windDeg)),
            windDeg: forecastItem.windDeg,
            description: forecastItem.weather.first?.description.capitalized ?? "Clear",
            iconName: forecastItem.weather.first?.iconName ?? "sun.max.fill",
            pop: forecastItem.pop,
            visibility: nil,
            uvIndex: forecastItem.uvi,
            nextHourSummary: nil,
            precipitationData: nil,
            upcomingConditionsSummary: nil
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
            uvIndex: insights.uvIndex,
            nextHourSummary: current.nextHourSummary,
            precipitationData: current.precipitationData,
            upcomingConditionsSummary: current.upcomingConditionsSummary
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
            windDeg: item.windDeg,
            summary: item.summary ?? "Weather data unavailable." 
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
