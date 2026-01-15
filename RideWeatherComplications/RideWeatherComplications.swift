//
//  RideWeatherComplications.swift
//  RideWeatherComplications
//
//  Created by Craig Faist on 1/12/26.
//

import WidgetKit
import SwiftUI

// 1. SHARED DATA MODELS
// We redefine this here so the Widget knows what "Weather" looks like
struct SharedWeatherSummary: Codable {
    let temperature: Int
    let feelsLike: Int
    let conditionIcon: String
    let windSpeed: Int
    let windDirection: String
    let pop: Int
    let generatedAt: Date
}

enum ComplicationMode {
    case readiness // Morning (5 AM - 11 AM)
    case ride      // Day (11 AM - 7 PM)
    case recovery  // Night (7 PM - 5 AM)
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let mode: ComplicationMode
    
    // Wellness Data
    let tsb: Double
    let readiness: Int
    let status: String
    
    // Weather Data
    let temp: Int
    let feelsLike: Int
    let windSpeed: Int
    let windDir: String
    let conditionIcon: String
}

// 2. TIMELINE PROVIDER
struct Provider: TimelineProvider {
    // ⚠️ MATCH THIS TO YOUR APP GROUP ID
    let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")
    
    func placeholder(in context: Context) -> ComplicationEntry {
        // Placeholder shows generic data
        ComplicationEntry(
            date: Date(),
            mode: .readiness,
            tsb: 5, readiness: 90, status: "Fresh",
            temp: 72, feelsLike: 70, windSpeed: 10, windDir: "NW", conditionIcon: "sun.max"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> ()) {
        let entry = createEntry(for: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> ()) {
        var entries: [ComplicationEntry] = []
        let currentDate = Date()
        
        // Generate an entry for every hour for the next 24 hours
        // This allows the watch to switch modes automatically
        for hourOffset in 0..<24 {
            if let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate) {
                entries.append(createEntry(for: entryDate))
            }
        }

        // Refresh at the end of this 24 hour batch
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
    
    // Helper to build an entry based on time of day
    private func createEntry(for date: Date) -> ComplicationEntry {
        // 1. Fetch TSB/Readiness
        let tsb = defaults?.double(forKey: "widget_tsb") ?? 0
        let readiness = defaults?.integer(forKey: "widget_readiness") ?? 0
        let status = defaults?.string(forKey: "widget_status") ?? "Unknown"
        
        // 2. Fetch Weather
        var temp = 0
        var feelsLike = 0
        var wind = 0
        var dir = "--"
        var icon = "questionmark"
        
        if let data = defaults?.data(forKey: "widget_weather_summary"),
           let weather = try? JSONDecoder().decode(SharedWeatherSummary.self, from: data) {
            temp = weather.temperature
            feelsLike = weather.feelsLike
            wind = weather.windSpeed
            dir = weather.windDirection
            icon = weather.conditionIcon
        }
        
        // 3. Determine Mode based on Hour
        let hour = Calendar.current.component(.hour, from: date)
        let mode: ComplicationMode
        
        switch hour {
        case 5..<11:  mode = .readiness // 5AM - 11AM: Morning Check
        case 11..<19: mode = .ride      // 11AM - 7PM: Ride Weather
        default:      mode = .recovery  // 7PM - 5AM: Recovery
        }
        
        return ComplicationEntry(
            date: date,
            mode: mode,
            tsb: tsb, readiness: readiness, status: status,
            temp: temp, feelsLike: feelsLike, windSpeed: wind, windDir: dir, conditionIcon: icon
        )
    }
}

// 3. THE VIEWS
struct RideWeatherComplicationsEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryCorner:
            cornerView
        case .accessoryInline:
            inlineView
        default:
            Text("\(Int(entry.tsb))")
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    var circularView: some View {
        switch entry.mode {
        case .readiness:
            // Morning: Show TSB
            Gauge(value: entry.tsb, in: -30...30) {
                Text("TSB")
            } currentValueLabel: {
                Text("\(Int(entry.tsb))")
                    .font(.system(size: 12, weight: .bold))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(tsbColor(entry.tsb))
            
        case .ride:
            // Day: Show Weather (Wind)
            VStack(spacing: 0) {
                Image(systemName: "wind")
                    .font(.system(size: 10))
                Text("\(entry.windSpeed)")
                    .font(.system(size: 14, weight: .bold))
                Text(entry.windDir)
                    .font(.system(size: 8))
            }
            
        case .recovery:
            // Night: Show Readiness
            Gauge(value: Double(entry.readiness), in: 0...100) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 10))
            } currentValueLabel: {
                Text("\(entry.readiness)")
                    .font(.system(size: 12, weight: .bold))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [.red, .yellow, .green]))
        }
    }
    
    @ViewBuilder
    var rectangularView: some View {
        switch entry.mode {
        case .readiness:
            VStack(alignment: .leading) {
                Text("MORNING FORM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(entry.status)
                        .font(.headline)
                        .widgetAccentable()
                    Spacer()
                    Text("TSB \(Int(entry.tsb))")
                        .font(.subheadline)
                        .foregroundStyle(tsbColor(entry.tsb))
                }
            }
            
        case .ride:
            // Cleaner, centered layout for Rectangular
            HStack {
                // Left: Temps
                VStack(alignment: .leading) {
                    Text("\(entry.temp)°")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.8)
                    
                    Text("Feels \(entry.feelsLike)°")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Stacked Wind Info (Icon + Speed + Dir)
                VStack(alignment: .trailing) {
                    Image(systemName: entry.conditionIcon) // Sun/Cloud icon
                        .font(.title3)
                    
                    HStack(spacing: 2) {
                        Image(systemName: "wind")
                            .font(.caption2)
                        Text("\(entry.windSpeed) \(entry.windDir)")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                }
            }
            
        case .recovery:
            HStack {
                VStack(alignment: .leading) {
                    Text("RECOVERY")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    Text("Ready: \(entry.readiness)%")
                        .font(.headline)
                }
                Spacer()
                Gauge(value: Double(entry.readiness), in: 0...100) {
                    Text("Rec")
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .frame(width: 50)
                .tint(.green)
            }
        }
    }
    
    @ViewBuilder
    var cornerView: some View {
        switch entry.mode {
        case .readiness:
            Text("\(entry.readiness)")
                .font(.title.bold())
                .widgetLabel("Readiness")
        case .ride:
            Image(systemName: "wind")
                .widgetLabel("\(entry.windSpeed) mph \(entry.windDir)")
        case .recovery:
            Image(systemName: "bed.double.fill")
                .widgetLabel("Recovery")
        }
    }
    
    @ViewBuilder
    var inlineView: some View {
        switch entry.mode {
        case .readiness:
            Text("Readiness: \(entry.readiness)%")
        case .ride:
            Text("\(entry.temp)° • Wind \(entry.windSpeed)\(entry.windDir)")
        case .recovery:
            Text("Recovery: Good")
        }
    }
    
    // Helper
    func tsbColor(_ val: Double) -> Color {
        if val > 10 { return .green }
        if val < -20 { return .red }
        return .yellow
    }
}

// 4. MAIN CONFIGURATION
@main
struct RideWeatherComplications: Widget {
    let kind: String = "RideWeatherComplications"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            RideWeatherComplicationsEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Smart Ride Stats")
        .description("Auto-switches between Form, Weather, and Recovery.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}
