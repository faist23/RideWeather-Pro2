//
//  WeatherMapper.swift
//

import Foundation

struct WeatherMapper {
    static func mapCurrentToDisplayModel(_ current: CurrentWeatherResponse) -> DisplayWeatherModel {
        DisplayWeatherModel(
            temp: current.main.temp,
            feelsLike: current.main.feelsLike,
            humidity: current.main.humidity,
            windSpeed: current.wind.speed,
            windDirection: current.wind.direction,
            windDeg: current.wind.deg,
            description: current.weather.first?.description.capitalized ?? "Clear",
            iconName: current.weather.first?.iconName ?? "sun.max.fill"
        )
    }

    static func mapForecastItemToDisplayModel(_ forecastItem: HourlyItem) -> DisplayWeatherModel {
        DisplayWeatherModel(
            temp: forecastItem.temp,
            feelsLike: forecastItem.feelsLike,
            humidity: 0,
            windSpeed: forecastItem.windSpeed,
            windDirection: forecastItem.windDirection,
            windDeg: forecastItem.windDeg,
            description: forecastItem.weather.first?.description.capitalized ?? "Clear",
            iconName: forecastItem.weather.first?.iconName ?? "sun.max.fill"
        )
    }

    static func mapForecastItemToUIModel(_ item: HourlyItem) -> HourlyForecast {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = Date(timeIntervalSince1970: item.dt)
        return HourlyForecast(
            time: formatter.string(from: date),
            iconName: item.weather.first?.iconName ?? "sun.max.fill",
            temp: item.temp,
            feelsLike: item.feelsLike,
            pop: item.pop,
            windSpeed: item.windSpeed,
            windDirection: item.windDirection,
            windDeg: item.windDeg
        )
    }

    static func mapHourlyItemToUIModel(_ item: HourlyItem) -> HourlyForecast {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = Date(timeIntervalSince1970: TimeInterval(item.dt))
        return HourlyForecast(
            id: UUID(),
            time: formatter.string(from: date),
            iconName: item.weather.first?.icon ?? "sun.max.fill",
            temp: item.temp,
            feelsLike: item.feelsLike,
            pop: item.pop,
            windSpeed: item.windSpeed,
            windDirection: getWindDirection(degrees: Double(item.windDeg)),
            windDeg: item.windDeg
        )
    }

    private static func getWindDirection(degrees: Double) -> String {
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
        let index = Int((degrees+11.25)/22.5) % 16
        return dirs[index]
    }
}
