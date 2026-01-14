//
//  RideWeatherComplications.swift
//  RideWeatherComplications
//
//  Created by Craig Faist on 1/12/26.
//

import WidgetKit
import SwiftUI

// 1. DATA MODEL
struct ComplicationEntry: TimelineEntry {
    let date: Date
    let tsb: Double
    let readiness: Int
    let status: String
}

// 2. TIMELINE PROVIDER (Reads from App Group)
struct Provider: TimelineProvider {
    // MATCH YOUR APP GROUP ID HERE
    let defaults = UserDefaults(suiteName: "group.com.ridepro.rideweather")
    
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), tsb: 5, readiness: 85, status: "Fresh")
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> ()) {
        completion(fetchData())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> ()) {
        let entry = fetchData()
        // Refresh every hour or when app manually reloads it
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
        completion(timeline)
    }
    
    func fetchData() -> ComplicationEntry {
        let tsb = defaults?.double(forKey: "widget_tsb") ?? 0
        let readiness = defaults?.integer(forKey: "widget_readiness") ?? 0
        let status = defaults?.string(forKey: "widget_status") ?? "Unknown"
        
        return ComplicationEntry(
            date: Date(),
            tsb: tsb,
            readiness: readiness,
            status: status
        )
    }
}

// 3. THE WIDGET CONFIGURATION
@main
struct RideWeatherComplications: Widget {
    let kind: String = "RideWeatherComplications"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            RideWeatherComplicationsEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Training/Readiness Stats")
        .description("Track your Form and Readiness.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}

// 4. THE VIEWS
struct RideWeatherComplicationsEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            // TSB Ring
            Gauge(value: entry.tsb, in: -30...30) {
                Text("TSB")
            } currentValueLabel: {
                Text("\(Int(entry.tsb))")
                    .font(.system(size: 12, weight: .bold))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(tsbColor(entry.tsb))
            
        case .accessoryRectangular:
            // Detailed Stats
            VStack(alignment: .leading) {
                Text("Form: \(entry.status)")
                    .font(.headline)
                    .widgetAccentable() // Allows user tinting
                Text("Readiness: \(entry.readiness)%")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
        case .accessoryCorner:
            // Readiness Score
            Text("\(entry.readiness)")
                .font(.title.bold())
                .widgetLabel("Readiness")
                
        default:
            Text("TSB: \(Int(entry.tsb))")
        }
    }
    
    func tsbColor(_ val: Double) -> Color {
        if val > 10 { return .green }
        if val < -20 { return .red }
        return .yellow
    }
}
