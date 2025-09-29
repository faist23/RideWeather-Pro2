//
//  ChartableWeatherPoint.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/18/25.
//


import SwiftUI
import Charts

// A data model that can be plotted on a chart
struct ChartableWeatherPoint: Identifiable {
    var id = UUID()
    let distance: Double
    let temp: Double
    let wind: Double
    let rain: Double
}

struct InteractiveWeatherChart: View {
    let analytics: RouteAnalyticsEngine
    @Binding var selectedDistance: Double? // For scrubbing
    
    // Prepare data for the chart
    private var chartData: [ChartableWeatherPoint] {
        analytics.weatherPoints.map { point in
            let distance = analytics.units == .metric ? point.distance / 1000 : point.distance / 1609.34
            return ChartableWeatherPoint(
                distance: distance,
                temp: point.weather.temp,
                wind: point.weather.windSpeed,
                rain: Double(point.weather.humidity)
            )
        }
    }
    
    var body: some View {
        Chart {
            ForEach(chartData) { point in
                // Temperature Line
                LineMark(
                    x: .value("Distance", point.distance),
                    y: .value("Temp", point.temp)
                )
                .foregroundStyle(.orange)
                .symbol(Circle().strokeBorder(lineWidth: 1.5))

                // Wind Area
                AreaMark(
                    x: .value("Distance", point.distance),
                    y: .value("Wind", point.wind)
                )
                .foregroundStyle(.cyan.opacity(0.3))

                // Rain Probability Bars
                BarMark(
                    x: .value("Distance", point.distance),
                    y: .value("Rain", point.rain)
                )
                .foregroundStyle(.blue.opacity(0.5))
                .annotation(position: .top) {
                    if point.rain > 85 {
                        Image(systemName: "cloud.rain.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            // RuleMark for scrubbing
            if let selectedDistance {
                RuleMark(x: .value("Selected", selectedDistance))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .annotation(position: .top, alignment: .leading) {
                        if let point = findClosestPoint(to: selectedDistance) {
                            scrubbingPopover(for: point)
                        }
                    }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            let unit = analytics.units == .metric ? "km" : "mi"
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel("\(value.as(Double.self) ?? 0, specifier: "%.0f") \(unit)")
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x
                                if let distance: Double = proxy.value(atX: x) {
                                    selectedDistance = distance
                                }
                            }
                            .onEnded { _ in
                                selectedDistance = nil
                            }
                    )
            }
        }
        .frame(height: 250)
    }
    
    private func findClosestPoint(to distance: Double) -> ChartableWeatherPoint? {
        chartData.min(by: { abs($0.distance - distance) < abs($1.distance - distance) })
    }
    
    @ViewBuilder
    private func scrubbingPopover(for point: ChartableWeatherPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mile \(point.distance, specifier: "%.1f")")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
            
            HStack {
                Image(systemName: "thermometer").foregroundStyle(.orange)
                Text("\(Int(point.temp))°")
            }
            HStack {
                Image(systemName: "wind").foregroundStyle(.cyan)
                Text("\(Int(point.wind)) \(analytics.units.speedUnitAbbreviation)")
            }
            HStack {
                Image(systemName: "drop.fill").foregroundStyle(.blue)
                Text("\(Int(point.rain))%")
            }
        }
        .font(.caption)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
    }
}