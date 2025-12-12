//
// AnalyticsCharts.swift
//

import Charts
import CoreLocation
import SwiftUI

struct ChartableWeatherPoint: Identifiable {
    var id = UUID()
    let distance: Double
    let temp: Double
    let feelsLike: Double
    let wind: Double
    let windDeg: Int
    let humidity: Double
    let chanceOfRain: Double
    var elevation: Double?
    let grade: Double?
}

struct InteractiveWeatherChart: View {
//    let analytics: RouteAnalyticsEngine
    let weatherPoints: [RouteWeatherPoint] // Ask for the data directly
    let units: UnitSystem                  // Ask for the units directly
    let elevationAnalysis: ElevationAnalysis?
    @Binding var selectedDistance: Double?

    @State private var chartData: [ChartableWeatherPoint] = []
    @State private var downsampledElevationData: [(distance: Double, elevation: Double)] = []
    
    // MARK: - Domain Calculations
    private var sharedXDomain: ClosedRange<Double> {
        let maxWeatherDistance = chartData.map(\.distance).max() ?? 0
        let maxElevationDistance = downsampledElevationData.map(\.distance).max() ?? 0
        let trueMaxDistance = max(maxWeatherDistance, maxElevationDistance)
        guard trueMaxDistance > 0 else { return 0...1 }
        return 0...(trueMaxDistance * 1.02)
    }

    private var weatherYDomain: ClosedRange<Double> {
        let maxFeelsLike = chartData.map(\.feelsLike).max() ?? 100
        let maxWind = chartData.map(\.wind).max() ?? 40
        let maxRain = chartData.map(\.chanceOfRain).max() ?? 100
        let upperBound = max(maxFeelsLike, maxWind, maxRain, 50) * 1.1
        return 0...upperBound
    }
    
    private var elevationYDomain: ClosedRange<Double> {
        let elevations = downsampledElevationData.map(\.elevation)
        guard !elevations.isEmpty, let minEl = elevations.min(), let maxEl = elevations.max()
        else { return 0...100 }
        let padding = (maxEl - minEl) * 0.1
        return (minEl - padding)...(maxEl + padding)
    }
    
    // MARK: - Main View Body
    var body: some View {
        ZStack {
            backgroundChartView
            foregroundChartView
        }
        .frame(height: 280)
        .onAppear(perform: prepareChartData)
        .onChange(of: weatherPoints.count) { prepareChartData() }
        .onChange(of: elevationAnalysis?.hasActualData) { prepareChartData() }
        .onChange(of: units) { prepareChartData() }
    }
    
    // MARK: - Chart Views
    @ViewBuilder
    private var backgroundChartView: some View {
        if elevationAnalysis?.hasActualData == true {
            Chart {
                let alignedData = alignElevationDataForDisplay()
                ForEach(alignedData, id: \.distance) { point in
                    AreaMark(
                        x: .value("Distance", point.distance),
                        yStart: .value("Elevation Start", elevationYDomain.lowerBound),
                        yEnd: .value("Elevation End", point.elevation)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.brown.opacity(0.1), .brown.opacity(0.4)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                }
            }
            .chartXScale(domain: sharedXDomain)
            .chartYScale(domain: elevationYDomain)
            .chartXAxis(.hidden)
            .chartYAxis {
                // VISIBLE Trailing Axis
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    let val = value.as(Double.self) ?? 0
                    AxisValueLabel("\(Int(val)) \(units == .metric ? "m" : "ft")")
                        .font(.caption2)
                        .foregroundStyle(.brown)
                }
                // INVISIBLE Leading Axis (Spacer)
                let weatherValues = stride(from: 0, through: weatherYDomain.upperBound, by: weatherYDomain.upperBound / 4).map { $0 }
                AxisMarks(position: .leading, values: weatherValues) {
                    AxisValueLabel().foregroundStyle(.clear)
                }
            }
        }
    }
    
    private var foregroundChartView: some View {
        Chart {
            // Feels Like Line
            let validTempData = chartData.filter { !$0.feelsLike.isNaN && !$0.feelsLike.isInfinite }
            ForEach(validTempData) { LineMark(x: .value("Distance", $0.distance),
                                              y: .value("Feels Like", $0.feelsLike))
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 3.0))
                .symbol(.circle)
                .symbolSize(50)
            }

            // Wind Area
            let validWindData = chartData.filter { !$0.wind.isNaN && !$0.wind.isInfinite && $0.wind >= 0 }
            ForEach(validWindData) { AreaMark(x: .value("Distance", $0.distance),
                                              yStart: .value("Wind Start", 0),
                                              yEnd: .value("Wind End", $0.wind))
                .foregroundStyle(.cyan.opacity(0.3))
            }

            // Chance of Rain Bars
            let validRainData = chartData.filter { !$0.chanceOfRain.isNaN && !$0.chanceOfRain.isInfinite }
            ForEach(validRainData) { BarMark(x: .value("Distance", $0.distance),
                                             y: .value("Chance of Rain", $0.chanceOfRain))
                .foregroundStyle(.blue.opacity(0.5))
            }

            // Vertical Rule for selected distance
            if let selectedDistance {
                RuleMark(x: .value("Selected", selectedDistance))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }
        }
        .chartXScale(domain: sharedXDomain)
        .chartYScale(domain: weatherYDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisTick()
                let unit = units == .metric ? "km" : "mi"
                AxisValueLabel("\(value.as(Double.self) ?? 0, specifier: "%.0f") \(unit)")
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel("\(Int(value.as(Double.self) ?? 0))")
            }
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                AxisValueLabel().font(.caption2).foregroundStyle(.clear)
            }
        }
        // Floating weather card overlay
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = value.location.x
                                    if let distance: Double = proxy.value(atX: x) {
                                        selectedDistance = max(sharedXDomain.lowerBound,
                                                               min(sharedXDomain.upperBound, distance))
                                    }
                                }
                                .onEnded { _ in selectedDistance = nil }
                        )

                    if let selectedDistance, let point = findClosestPoint(to: selectedDistance) {
                        let xPos = proxy.position(forX: selectedDistance) ?? 0
                        scrubbingPopover(for: point)
                            .frame(maxWidth: 220) // wide enough for text
                            .position(
                                x: min(max(xPos, 110), geometry.size.width - 110), // prevent clipping
                                y: geometry.size.height / 2 // vertically centered
                            )
                    }
                }
            }
        }
    }

    // MARK: - Data Preparation & Helpers
    
    private func alignElevationDataForDisplay() -> [(distance: Double, elevation: Double)] {
        guard !downsampledElevationData.isEmpty else { return [] }
        var displayData = downsampledElevationData
        
        // Pad the start if necessary
        if let firstPoint = displayData.first, firstPoint.distance > 0 {
            displayData.insert((distance: 0, elevation: firstPoint.elevation), at: 0)
        }
        
        // No need to extend - the domain should match the data exactly now
        return displayData
    }

    private func chartInteractionOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x
                                if let distance: Double = proxy.value(atX: x) {
                                    selectedDistance = max(
                                        sharedXDomain.lowerBound,
                                        min(sharedXDomain.upperBound, distance)
                                    )
                                }
                            }
                            .onEnded { _ in selectedDistance = nil }
                    )

                if let selectedDistance, let point = findClosestPoint(to: selectedDistance) {
                    // Compute X position in the chart
                    let xPos = proxy.position(forX: selectedDistance) ?? 0
                    // Center the popover horizontally
                    scrubbingPopover(for: point)
                        .frame(maxWidth: 220) // or whatever max width works for legibility
                        .position(x: min(max(xPos, 110), geometry.size.width - 110), // prevents clipping
                                  y: geometry.size.height / 2) // vertically centered
                }
            }
        }
    }

    
    private func prepareChartData() {
        let distanceConverter: (Double) -> Double = { $0 / (units == .metric ? 1000.0 : 1609.34) }
        let elevationConverter: (Double) -> Double = { $0 * (units == .metric ? 1.0 : 3.28084) }
        let profile = elevationAnalysis?.elevationProfile ?? []
        let fullElevationProfile = profile.map { (distance: distanceConverter($0.distance), elevation: elevationConverter($0.elevation)) }
        self.downsampledElevationData = simplifyElevationData(fullElevationProfile, maxPoints: 200)
        
        // Get the max elevation distance to constrain weather data
        let maxElevationDistance = fullElevationProfile.map(\.distance).max() ?? Double.greatestFiniteMagnitude
        
        let keyWeatherPoints = weatherPoints.sorted { $0.distance < $1.distance }
        guard !keyWeatherPoints.isEmpty else {
            self.chartData = []
            return
        }
        var processedChartData: [ChartableWeatherPoint] = []
        for weatherPoint in keyWeatherPoints {
            var chartPoint = mapToChartable(weatherPoint: weatherPoint, distanceConverter: distanceConverter)
            
            // Only include weather points that are within the elevation profile range
            if chartPoint.distance <= maxElevationDistance {
                if elevationAnalysis?.hasActualData == true {
                    let elevationAtPoint = findElevationAt(distance: chartPoint.distance, elevationProfile: fullElevationProfile)
                    chartPoint.elevation = elevationAtPoint
                }
                processedChartData.append(chartPoint)
            }
        }
        self.chartData = processedChartData
    }
    
    private func findElevationAt(distance: Double, elevationProfile: [(distance: Double, elevation: Double)]) -> Double {
        guard !elevationProfile.isEmpty else { return 0 }
        let closest = elevationProfile.min { abs($0.distance - distance) < abs($1.distance - distance) }
        return closest?.elevation ?? 0
    }
    
    private func mapToChartable(weatherPoint: RouteWeatherPoint, distanceConverter: (Double) -> Double) -> ChartableWeatherPoint {
        let weather = weatherPoint.weather
        return ChartableWeatherPoint(
            distance: distanceConverter(weatherPoint.distance),
            temp: weather.temp,
            feelsLike: weather.feelsLike,
            wind: weather.windSpeed,
            windDeg: weather.windDeg,
            humidity: Double(weather.humidity),
            chanceOfRain: weather.pop * 100,
            elevation: nil,
            grade: nil
        )
    }

    private func simplifyElevationData(_ points: [(distance: Double, elevation: Double)], maxPoints: Int) -> [(distance: Double, elevation: Double)] {
        guard points.count > maxPoints else { return points }
        let step = max(1, points.count / maxPoints)
        var result: [(distance: Double, elevation: Double)] = []
        for i in stride(from: 0, to: points.count, by: step) {
            result.append(points[i])
        }
        if let last = points.last, result.last?.distance != last.distance {
            result.append(last)
        }
        return result
    }
    
    private func findClosestPoint(to distance: Double) -> ChartableWeatherPoint? {
        chartData.min(by: { abs($0.distance - distance) < abs($1.distance - distance) })
    }
    
    private func popoverAlignment(for selectedDistance: Double) -> Alignment {
        guard (sharedXDomain.upperBound - sharedXDomain.lowerBound) > 0 else { return .top }
        let progress = (selectedDistance - sharedXDomain.lowerBound) / (sharedXDomain.upperBound - sharedXDomain.lowerBound)
        if progress < 0.2 { return .topLeading }
        if progress > 0.8 { return .topTrailing }
        return .top
    }

    @ViewBuilder
    private func scrubbingPopover(for point: ChartableWeatherPoint) -> some View {
        VStack(spacing: 12) {
            let unit = units == .metric ? "km" : "mi"
            Text("\(unit == "km" ? "Kilometer" : "Mile") \(point.distance, specifier: "%.1f")")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "thermometer").foregroundStyle(.red).frame(width: 16)
                    Text("\(Int(point.temp))°").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
                HStack(spacing: 8) {
                    Image(systemName: "thermometer.sun.fill").foregroundStyle(.orange).frame(width: 16)
                    Text("Feels \(Int(point.feelsLike))°").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
                HStack(spacing: 8) {
                    Image(systemName: "wind").foregroundStyle(.cyan).frame(width: 16)
                    Image(systemName: "arrow.up")
                         .font(.caption)
                         .rotationEffect(.degrees(Double(point.windDeg) + 180))
                    Text("\(Int(point.wind)) \(units.speedUnitAbbreviation)").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
                HStack(spacing: 8) {
                    Image(systemName: "drop.fill").foregroundStyle(.blue).frame(width: 16)
                    Text("\(Int(point.chanceOfRain))%").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}
