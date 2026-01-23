//
//  RideWeatherComplications.swift
//  RideWeatherComplications
//
//  Updated: Now includes 3 complications total
//  1. Smart Ride Stats (original - switches by time of day)
//  2. Ride Weather (new - always shows weather)
//  3. Steps (new - always shows steps)
//

import WidgetKit
import SwiftUI

// MARK: - Shared Data Models

// MARK: - Shared Data Model
struct SharedWeatherSummary: Codable {
    let temperature: Int
    let feelsLike: Int
    let conditionIcon: String
    let windSpeed: Int
    let windDirection: String
    let pop: Int
    let generatedAt: Date
    let alertSeverity: String? // NEW
}

enum ComplicationMode {
    case readiness // Morning (5 AM - 11 AM)
    case ride      // Day (11 AM - 7 PM)
    case recovery  // Night (7 PM - 5 AM)
}

// MARK: - Entry for Smart Ride Stats (Original)

struct SmartRideStatsEntry: TimelineEntry {
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

// MARK: - Entry
struct SimpleComplicationEntry: TimelineEntry {
    let date: Date
    
    // Weather Data
    let temp: Int
    let feelsLike: Int
    let windSpeed: Int
    let windDir: String
    let conditionIcon: String
    
    // Alert Data
    let alertSeverity: String? // NEW
    
    // Steps Data
    let todaySteps: Int
}

// MARK: - Timeline Provider for Smart Ride Stats (Original)

struct SmartRideStatsProvider: TimelineProvider {
    let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")
    
    func placeholder(in context: Context) -> SmartRideStatsEntry {
        SmartRideStatsEntry(
            date: Date(),
            mode: .readiness,
            tsb: 5, readiness: 90, status: "Fresh",
            temp: 72, feelsLike: 70, windSpeed: 10, windDir: "NW", conditionIcon: "sun.max"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SmartRideStatsEntry) -> ()) {
        let entry = createEntry(for: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SmartRideStatsEntry>) -> ()) {
        Task {
            // Fetch fresh data every refresh
            await WidgetDataFetcher.shared.fetchAllData()
            
            var entries: [SmartRideStatsEntry] = []
            let currentDate = Date()
            
            for hourOffset in 0..<24 {
                if let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate) {
                    entries.append(createEntry(for: entryDate))
                }
            }

            // Refresh every hour
            let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
            let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
            completion(timeline)
        }
    }
    
    private func createEntry(for date: Date) -> SmartRideStatsEntry {
        let tsb = defaults?.double(forKey: "widget_tsb") ?? 0
        let readiness = defaults?.integer(forKey: "widget_readiness") ?? 0
        let status = defaults?.string(forKey: "widget_status") ?? "Unknown"
        
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
        
        let hour = Calendar.current.component(.hour, from: date)
        let mode: ComplicationMode
        
        switch hour {
        case 5..<11:  mode = .readiness
        case 11..<19: mode = .ride
        default:      mode = .recovery
        }
        
        return SmartRideStatsEntry(
            date: date,
            mode: mode,
            tsb: tsb, readiness: readiness, status: status,
            temp: temp, feelsLike: feelsLike, windSpeed: wind, windDir: dir, conditionIcon: icon
        )
    }
}

// MARK: - Provider
struct SimpleComplicationProvider: TimelineProvider {
    let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")
    
    func placeholder(in context: Context) -> SimpleComplicationEntry {
        SimpleComplicationEntry(
            date: Date(),
            temp: 72, feelsLike: 70, windSpeed: 10, windDir: "NW", conditionIcon: "sun.max",
            alertSeverity: nil,
            todaySteps: 8543
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleComplicationEntry) -> ()) {
        completion(createEntry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleComplicationEntry>) -> ()) {
            Task {
                // ✅ CRITICAL FIX: Actually fetch fresh data (including alerts)
                await WidgetDataFetcher.shared.fetchAllData()
                
                let entry = createEntry(for: Date())
                
                // Refresh every 30 minutes
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                
                completion(timeline)
            }
        }
    
    private func createEntry(for date: Date) -> SimpleComplicationEntry {
        var temp = 0
        var feelsLike = 0
        var wind = 0
        var dir = "--"
        var icon = "questionmark"
        var alert: String? = nil
        
        if let data = defaults?.data(forKey: "widget_weather_summary"),
           let weather = try? JSONDecoder().decode(SharedWeatherSummary.self, from: data) {
            temp = weather.temperature
            feelsLike = weather.feelsLike
            wind = weather.windSpeed
            dir = weather.windDirection
            icon = weather.conditionIcon
            alert = weather.alertSeverity // Load Alert
        }
        
        let todaySteps = defaults?.integer(forKey: "widget_today_steps") ?? 0
        
        return SimpleComplicationEntry(
            date: date,
            temp: temp, feelsLike: feelsLike, windSpeed: wind, windDir: dir, conditionIcon: icon,
            alertSeverity: alert,
            todaySteps: todaySteps
        )
    }
}

// MARK: - Smart Ride Stats View (Original)

struct SmartRideStatsEntryView: View {
    var entry: SmartRideStatsProvider.Entry
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
    
    @ViewBuilder
    var circularView: some View {
        switch entry.mode {
        case .readiness:
            Gauge(value: entry.tsb, in: -30...30) {
                Text("TSB")
            } currentValueLabel: {
                Text("\(Int(entry.tsb))")
                    .font(.system(size: 12, weight: .bold))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(tsbColor(entry.tsb))
            
        case .ride:
            VStack(spacing: 1) {
                Text("\(entry.temp)°")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("FL \(entry.feelsLike)°")
                    .font(.system(size: 12, weight: .regular, design: .rounded))

                HStack(spacing: 1) {
                    Image(systemName: "wind")
                        .font(.system(size: 8))
                        .symbolRenderingMode(.hierarchical)
                    Text("\(entry.windSpeed)")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            
        case .recovery:
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
            HStack {
                VStack(alignment: .leading) {
                    Text("\(entry.temp)°")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.8)
                    
                    Text("Feels \(entry.feelsLike)°")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Image(systemName: entry.conditionIcon)
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
            Text("\(entry.temp)°")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .widgetLabel {
                    Image(systemName: "wind")
                    Text("\(entry.windSpeed) \(entry.windDir)  FL \(entry.feelsLike)°")
                }
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
            Text("Feels \(entry.feelsLike)° • Wind \(entry.windSpeed) \(entry.windDir)")
        case .recovery:
            Text("Recovery: Good")
        }
    }
    
    func tsbColor(_ val: Double) -> Color {
        if val > 10 { return .green }
        if val < -20 { return .red }
        return .yellow
    }
}

// MARK: - Weather View
struct RideWeatherComplicationEntryView: View {
    var entry: SimpleComplicationProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var destinationURL: URL {
        if entry.alertSeverity != nil {
            return URL(string: "rideweather://weather")! // weather was alert to go to alert tab
        }
        return URL(string: "rideweather://weather")!
    }
    
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularView
            case .accessoryCorner:
                cornerView
            case .accessoryInline:
                inlineView
            default:
                Text("\(entry.temp)°")
            }
        }
        .widgetURL(destinationURL)
    }
    
    @ViewBuilder
    var circularView: some View {
            VStack(spacing: 0) {
                // 1. Temperature (Always Visible)
                Text("\(entry.temp)°")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.8)
                
                // 2. Feels Like (Always Visible)
                Text("FL \(entry.feelsLike)°")
                    .font(.system(size: 8))
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.secondary)
                
                // 3. Icon Slot: Shows Alert Triangle OR Weather Icon
                if entry.alertSeverity != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(alertColor) // Red/Yellow
                        .padding(.top, 1)
                } else {
                    Image(systemName: entry.conditionIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(.blue.opacity(0.8))
                        .padding(.top, 1)
                }
            }
        }
    
    @ViewBuilder
    var cornerView: some View {
        HStack(spacing: 2) {
            // 1. Icon (Only if Alert)
            if entry.alertSeverity != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(alertColor)
                    .imageScale(.medium)
            }
            
            // 2. Temperature (Scales to fit)
            Text("\(entry.temp)°")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.3) // Crucial: Allows text to shrink instead of wrapping
                .lineLimit(1)            // Crucial: Forces single line
        }
        .widgetLabel {
            // 3. Label (ALWAYS Data, NEVER Alert Text)
            Image(systemName: "wind")
                        Text("\(entry.windSpeed) \(entry.windDir) • FL \(entry.feelsLike)°")
                    }
    }
    
    @ViewBuilder
    var inlineView: some View {
            if let severity = entry.alertSeverity {
                // "⚠️ 72° • Severe Warning"
                Text("⚠️ \(entry.temp)° • \(severity.capitalized) Alert")
                    .foregroundStyle(alertColor)
            } else {
                Text("Feels \(entry.feelsLike)° • Wind \(entry.windSpeed) \(entry.windDir)")
            }
        }
    
    var alertColor: Color {
        if entry.alertSeverity == "severe" { return .red }
        return .yellow
    }
}

// MARK: - Steps View (New)

struct StepsComplicationEntryView: View {
    var entry: SimpleComplicationProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
                .widgetURL(URL(string: "rideweather://steps")!)
        case .accessoryCorner:
            cornerView
                .widgetURL(URL(string: "rideweather://steps")!)
        case .accessoryInline:
            inlineView
                .widgetURL(URL(string: "rideweather://steps")!)
        default:
            Text("\(entry.todaySteps)")
                .widgetURL(URL(string: "rideweather://steps")!)
        }
    }
    
    @ViewBuilder
    var circularView: some View {
        VStack(spacing: 2) {
            Image(systemName: "figure.walk")
                .font(.system(size: 12))
                .foregroundStyle(.green)
            
            Text(formatSteps(entry.todaySteps))
                .font(.system(size: 16, weight: .bold, design: .rounded))
            
            Text("steps")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    var cornerView: some View {
        Image(systemName: "figure.walk")
            .font(.system(size: 24))
            .widgetLabel {
                Text("\(formatSteps(entry.todaySteps)) steps")
            }
    }
    
    @ViewBuilder
    var inlineView: some View {
        Text("\(formatSteps(entry.todaySteps)) steps")
    }
    
    private func formatSteps(_ steps: Int) -> String {
        if steps >= 10000 {
            let thousands = Double(steps) / 1000.0
            return String(format: "%.1fk", thousands)
        }
        return "\(steps)"
    }
}

// MARK: - Widget Configurations

@main
struct RideWeatherComplicationsBundle: WidgetBundle {
    var body: some Widget {
        SmartRideStatsWidget()
        RideWeatherComplication()
        StepsComplication()
    }
}

struct SmartRideStatsWidget: Widget {
    let kind: String = "SmartRideStatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SmartRideStatsProvider()) { entry in
            SmartRideStatsEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Smart Ride Stats")
        .description("Auto-switches between Form, Weather, and Recovery.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}

struct RideWeatherComplication: Widget {
    let kind: String = "RideWeatherComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SimpleComplicationProvider()) { entry in
            RideWeatherComplicationEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Ride Weather")
        .description("Current temperature, feels like, and wind conditions.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct StepsComplication: Widget {
    let kind: String = "StepsComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SimpleComplicationProvider()) { entry in
            StepsComplicationEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Steps")
        .description("Today's step count and progress toward goal.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}
