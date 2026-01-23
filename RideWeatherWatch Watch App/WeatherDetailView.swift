//
//  WeatherDetailView.swift
//  RideWeatherWatch Watch App
//
//  Design: "Cockpit Density" - Temp Left, Conditions Right.
//  Added: "Last Updated" timestamp from data source.
//

import SwiftUI

struct WeatherDetailView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    @EnvironmentObject var navigationManager: NavigationManager // Access nav manager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                
                if let weather = loadWeatherData() {
                    
                    // --- ACTIVE ALERT BANNER ---
                    // Links directly to the Alert Tab
                    if let alert = session.weatherAlert {
                        Button {
                            withAnimation {
                                navigationManager.selectedTab = .alert
                            }
                        } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.headline)
                                        .symbolEffect(.pulse, isActive: true)
                                        .foregroundStyle(.black) // KEEPING THIS BLACK
                                    
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text("ACTIVE ALERT")
                                            .font(.system(size: 9, weight: .black))
                                            .foregroundStyle(.black) // KEEPING THIS BLACK
                                        
                                        Text(alert.message.prefix(20))
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .foregroundStyle(.black) // KEEPING THIS BLACK
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.black.opacity(0.6))
                                }
                            .padding(8)
                            .background(alert.severity == .severe ? Color.red : (alert.severity == .warning ? Color.orange : Color.yellow))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain) // Remove default button chrome
                        .padding(.top, 4)
                    }
                    
                    // --- PRIMARY DASHBOARD ---
                    HStack(alignment: .center, spacing: 8) {
                        
                        // LEFT: Temperature
                        VStack(spacing: -2) {
                            HStack(alignment: .top, spacing: 2) {
                                Text("\(weather.temperature)")
                                    .font(.system(size: 56, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                
                                Text("°")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                            }
                            
                            HStack(spacing: 4) {
                                Image(systemName: weather.conditionIcon)
                                Text("FL \(weather.feelsLike)°")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(.secondary)
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
                    .padding(.top, session.weatherAlert == nil ? 4 : 0) // Adjust padding if banner exists
                    
                    // ... (Rest of view remains the same) ...
                    
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
        .containerBackground(.blue.gradient, for: .navigation) // Fixes Deep Links
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
    
    private func weatherColor(_ temp: Int) -> Color {
        if temp < 50 { return .cyan }
        if temp > 85 { return .orange }
        return .green
    }
    
    private func rideAdvice(temp: Int, wind: Int) -> String {
        if wind > 20 { return "High winds. Be careful." }
        if temp < 40 { return "Cold! Layer up properly." }
        if temp > 85 { return "Heat warning. Hydrate." }
        return "Conditions are good for riding."
    }
}

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

