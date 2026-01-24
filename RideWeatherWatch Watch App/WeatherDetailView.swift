//
//  WeatherDetailView.swift
//  RideWeatherWatch Watch App
//
//  Design: "Cockpit Density" - Temp Left, Conditions Right.
//  Updated: More prominent feels-like temperature display
//

import SwiftUI

struct WeatherDetailView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    @EnvironmentObject var navigationManager: NavigationManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                
                if let weather = loadWeatherData() {
                    
                    // Check the array for the first alert
                    if let alert = session.weatherAlerts.first {
                        Button {
                            withAnimation {
                                navigationManager.selectedTab = .alert(0)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.headline)
                                    .symbolEffect(.pulse, isActive: true)
                                    .foregroundStyle(.black)
                                
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("ACTIVE ALERT")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundStyle(.black)
                                    
                                    Text(alert.message.prefix(20))
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .foregroundStyle(.black)
                                }
                                Spacer()
                                
                                // MULTI-ALERT INDICATOR
                                // If we have more than 1 alert, show a small badge
                                if session.weatherAlerts.count > 1 {
                                    Text("+\(session.weatherAlerts.count - 1)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.black)
                                        .padding(4)
                                        .background(Color.white.opacity(0.4))
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.black.opacity(0.6))
                                }
                            }
                            .padding(8)
                            .background(alert.severity == .severe ? Color.red : (alert.severity == .warning ? Color.orange : Color.yellow))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    
                    // --- PRIMARY DASHBOARD ---
                    HStack(alignment: .center, spacing: 8) {
                        
                        // LEFT: Temperature
                        VStack(spacing: 2) {
                            HStack(alignment: .top, spacing: 2) {
                                Text("\(weather.temperature)")
                                    .font(.system(size: 56, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                
                                Text("°")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                            }
                            
                            // Updated Feels Like - more prominent
                            HStack(spacing: 4) {
                                Image(systemName: weather.conditionIcon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                
                                VStack(spacing: 0) {
                                    Text("Feels")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    
                                    Text("\(weather.feelsLike)°")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        // RIGHT: Wind & Conditions
                        VStack(alignment: .leading, spacing: 6) {
                            // Wind
                            CompactMetricRow(
                                icon: "wind",
                                value: "\(weather.windSpeed)",
                                unit: "mph",
                                color: windColor(weather.windSpeed)
                            )
                            
                            // Rain
                            CompactMetricRow(
                                icon: "drop.fill",
                                value: "\(weather.pop)",
                                unit: "%",
                                color: .cyan
                            )
                            
                            Text(weather.conditionIcon.contains("sun") ? "Clear" : "Cloudy")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, session.weatherAlerts.isEmpty ? 4 : 0)
                    // Footer
                    Text("Updated: \(weather.generatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    
                } else {
                    ContentUnavailableView("No Data", systemImage: "cloud.slash")
                }
            }
            .padding(.horizontal)
        }
        .containerBackground(.blue.gradient, for: .tabView)
        .containerBackground(.blue.gradient, for: .navigation)
    }
    
    // MARK: - Logic
    
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
}

struct WeatherSummaryData: Codable {
    let temperature: Int
    let feelsLike: Int
    let conditionIcon: String
    let windSpeed: Int
    let windDirection: String
    let pop: Int
    let generatedAt: Date
}
