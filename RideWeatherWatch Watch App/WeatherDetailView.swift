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
    
    private let topScrollID = "SCROLL_TOP"
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    
                    Color.clear
                        .frame(height: 1)
                        .id(topScrollID)
                    
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
                        
                        if let forecasts = weather.hourlyForecast?.prefix(8), !forecasts.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("NEXT 8 HOURS")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 4)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(Array(forecasts.enumerated()), id: \.element.id) { index, hour in                                            VStack(spacing: 4) {
                                            Text(hour.time.formatted(.dateTime.hour()))
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.secondary)
                                            
                                            Image(systemName: hour.icon)
                                                .font(.system(size: 14))
                                                .foregroundStyle(.blue)
                                            
                                            VStack(spacing: 0) {
                                                Text("\(hour.temp)°")
                                                    .font(.system(size: 16, weight: .bold))
                                                
                                                Text("(\(hour.feelsLike)°)")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.secondary)
                                            }
                                            
                                            HStack(spacing: 2) {
                                                Image(systemName: "wind")
                                                    .font(.system(size: 8))
                                                Text("\(hour.windSpeed)")
                                                    .font(.system(size: 10, weight: .bold))
                                            }
                                            .foregroundStyle(windColor(hour.windSpeed))
                                        }
                                        .frame(width: 45)
                                        .padding(.vertical, 6)
                                        .background(Color.white.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .id(index == 0 ? "FORECAST_START" : hour.id.description)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                        
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
            // Trigger 1: Handles manual swipes
            .onChange(of: navigationManager.selectedTab) { oldValue, newValue in
                if newValue == .weather {
                    scrollToTop(proxy)
                }
            }
            // Trigger 2: Handles complication taps even if already on weather tab
            .onChange(of: navigationManager.weatherResetTrigger) {
                scrollToTop(proxy)
            }
        }
        .containerBackground(.blue.gradient, for: .tabView)
        .containerBackground(.blue.gradient, for: .navigation)
    }
    
    private func scrollToTop(_ proxy: ScrollViewProxy) {
        // Small delay ensures the view has finished its transition or deep link processing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring()) {
                // 1. Reset the main vertical page to the top
                proxy.scrollTo(topScrollID, anchor: .top)
                
                // 2. Reset the horizontal forecast to the first hour
                proxy.scrollTo("FORECAST_START", anchor: .leading)
            }
        }
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
    let hourlyForecast: [ForecastHour]?
}

struct ForecastHour: Codable, Identifiable {
    var id: Date { time }
    let time: Date
    let temp: Int
    let feelsLike: Int
    let windSpeed: Int
    let icon: String
}
