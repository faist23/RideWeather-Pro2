//
//  WeatherDetailView.swift
//  RideWeatherWatch Watch App
//

import SwiftUI

// Local copy of SharedWeatherSummary for this file
struct WeatherSummaryData: Codable {
    let temperature: Int
    let feelsLike: Int
    let conditionIcon: String
    let windSpeed: Int
    let windDirection: String
    let pop: Int
    let generatedAt: Date
}

struct WeatherDetailView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // HEADER
                Text("RIDE CONDITIONS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                
                if let weatherData = loadWeatherData() {
                    // MAIN TEMP
                    VStack(spacing: 4) {
                        Text("\(weatherData.temperature)°")
                            .font(.system(size: 60, weight: .black, design: .rounded))
                        
                        HStack(spacing: 4) {
                            Image(systemName: weatherData.conditionIcon)
                                .font(.title3)
                            Text("Feels like \(weatherData.feelsLike)°")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                    
                    // WIND DETAILS
                    VStack(spacing: 8) {
                        DetailRow(
                            icon: "wind",
                            label: "Wind Speed",
                            value: "\(weatherData.windSpeed) mph",
                            color: windColor(weatherData.windSpeed)
                        )
                        
                        DetailRow(
                            icon: "location.north.fill",
                            label: "Direction",
                            value: weatherData.windDirection,
                            color: .blue
                        )
                        
                        DetailRow(
                            icon: "drop.fill",
                            label: "Rain Chance",
                            value: "\(weatherData.pop)%",
                            color: .cyan
                        )
                    }
                    
                    // RIDE RECOMMENDATION
                    VStack(spacing: 6) {
                        Text("RIDE ADVICE")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        
                        Text(rideAdvice(temp: weatherData.temperature, wind: weatherData.windSpeed))
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                    }
                    .padding(.top, 8)
                    
                } else {
                    ContentUnavailableView(
                        "No Weather Data",
                        systemImage: "cloud.slash",
                        description: Text("Sync from iPhone")
                    )
                }
            }
            .padding()
        }
        .containerBackground(.blue.gradient, for: .navigation)
        .navigationTitle("Weather")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func loadWeatherData() -> WeatherSummaryData? {
        let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")
        guard let data = defaults?.data(forKey: "widget_weather_summary"),
              let weather = try? JSONDecoder().decode(WeatherSummaryData.self, from: data) else {
            return nil
        }
        return weather
    }
    
    private func windColor(_ speed: Int) -> Color {
        switch speed {
        case 0..<10: return .green
        case 10..<20: return .yellow
        default: return .red
        }
    }
    
    private func rideAdvice(temp: Int, wind: Int) -> String {
        if wind > 20 {
            return "Strong winds - consider an indoor ride or protected route"
        } else if temp < 40 {
            return "Cold temps - layer up and watch for ice"
        } else if temp > 85 {
            return "Hot weather - hydrate well and consider early morning rides"
        } else if wind < 10 && temp >= 60 && temp <= 75 {
            return "Perfect conditions - enjoy your ride!"
        } else {
            return "Good conditions for riding"
        }
    }
}
