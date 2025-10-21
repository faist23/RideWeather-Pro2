//
//  AnalyticsDashboardView.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/15/25.
//

import SwiftUI
import Charts

// MARK: - Analytics Dashboard View

struct AnalyticsDashboardView: View {
    let hourlyData: [HourlyForecast]
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedMetric: AnalyticMetric = .comfort
    @State private var timeRange: TimeRange = .twentyFour
    @State private var selectedForecast: HourlyForecast?

    // MARK: - Enums
    enum TimeRange: String, CaseIterable, Identifiable {
        case twelve = "12h"
        case twentyFour = "24h"
        case fortyEight = "48h"
        
        var id: String { rawValue }
        var hours: Int {
            switch self {
            case .twelve: return 12
            case .twentyFour: return 24
            case .fortyEight: return 48
            }
        }
        var displayName: String {
            switch self {
            case .twelve: return "Next 12 Hours"
            case .twentyFour: return "Next 24 Hours"
            case .fortyEight: return "Next 48 Hours"
            }
        }
    }
    
    enum AnalyticMetric: String, CaseIterable, Identifiable {
        case comfort = "Cycling Comfort"
        case temperature = "Temperature"
        case wind = "Wind Analysis"
        case precipitation = "Precipitation"
        case optimal = "Optimal Times"
        
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .comfort: return "heart.fill"
            case .temperature: return "thermometer"
            case .wind: return "wind"
            case .precipitation: return "cloud.rain"
            case .optimal: return "star.fill"
            }
        }
        var color: Color {
            switch self {
            case .comfort: return .green
            case .temperature: return .orange
            case .wind: return .cyan
            case .precipitation: return .blue
            case .optimal: return .yellow
            }
        }
    }
    
    // MARK: - Computed Properties
    private var filteredData: [HourlyForecast] {
        let sortedData = hourlyData.sorted { $0.date < $1.date }
        return Array(sortedData.prefix(timeRange.hours))
    }
    
    private var xAxisStride: Int {
        switch timeRange {
        case .twelve:
            return 3
        case .twentyFour:
            return 6
        case .fortyEight:
            return 12
        }
    }

    // ✅ NEW: Computed property to format the best hour with the day
    private var formattedBestHour: String {
        guard let best = bestHour else { return "N/A" }
        let formatter = DateFormatter()
        formatter.dateFormat = "E h a" // Format for "Day Hour AM/PM" (e.g., "Mon 7 PM")
        return formatter.string(from: best.date)
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    quickStatsGrid
                    timeRangeSelector
                    metricSelector
                    mainChart
                    detailedAnalysis
                    smartRecommendations
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .background(backgroundGradient.ignoresSafeArea())
            .navigationTitle("Weather Analytics")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var quickStatsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
            AnalyticsStatCard(
                icon: "star.fill",
                title: "Best Hour",
                // ✅ CHANGED: Use the new formatted property for clarity
                value: formattedBestHour,
                subtitle: "\(analyticsHelper.averageComfort)% comfort",
                color: .yellow
            )
            
            VStack(spacing: 8) {
                ComfortGauge(value: analyticsHelper.averageComfort)
                    .frame(width: 65, height: 65)
                
                Text("Avg Comfort")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Overall score")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            
            AnalyticsStatCard(
                icon: "cloud.rain.fill",
                title: "Max Rain",
                value: "\(Int(maxRainChance * 100))%",
                subtitle: "Peak chance",
                color: .blue
            )
            
            AnalyticsStatCard(
                icon: "wind",
                title: "Max Wind",
                value: analyticsHelper.windRangeFormatted,
                subtitle: "Peak speed",
                color: .cyan
            )
        }
    }

    private var timeRangeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Time Range", systemImage: "clock.arrow.circlepath")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            
            Picker("Time Range", selection: $timeRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.displayName).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    private var metricSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Analysis Type", systemImage: "chart.xyaxis.line")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AnalyticMetric.allCases) { metric in
                        Button {
                            withAnimation(.bouncy) {
                                selectedMetric = metric
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: metric.icon)
                                    .symbolRenderingMode(.hierarchical)
                                Text(metric.rawValue)
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                selectedMetric == metric ?
                                    metric.color.opacity(0.3) :
                                    .white.opacity(0.1),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        selectedMetric == metric ?
                                            metric.color :
                                            .white.opacity(0.3),
                                        lineWidth: 2
                                    )
                            )
                        }
                        .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
 /*   private var mainChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("\(selectedMetric.rawValue) Trends", systemImage: selectedMetric.icon)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            if selectedForecast == nil {
                Text("Tap or drag on the chart to see details")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(height: 60, alignment: .center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            } else {
                Spacer().frame(height: 60)
            }

            if #available(iOS 16.0, *), !filteredData.isEmpty {
                let xDomain = (filteredData.first?.date ?? Date())...(filteredData.last?.date ?? Date())

                Chart(filteredData, id: \.id) { hour in
                    switch selectedMetric {
                    case .comfort:
                        // ✅ CHANGED: Pass idealTemp to comfort function
                        AreaMark(x: .value("Time", hour.date), y: .value("Comfort", hour.enhancedCyclingComfort(using: viewModel.settings.units, idealTemp: viewModel.settings.idealTemperature, uvIndex: hour.uvIndex, aqi: hour.aqi) * 100))
                            .foregroundStyle(.linearGradient(colors: [selectedMetric.color.opacity(0.8), selectedMetric.color.opacity(0.2)], startPoint: .top, endPoint: .bottom))

                    case .temperature:
                        LineMark(x: .value("Time", hour.date), y: .value("Temperature", hour.temp))
                            .foregroundStyle(selectedMetric.color)
                        LineMark(x: .value("Time", hour.date), y: .value("Feels Like", hour.feelsLike))
                            .foregroundStyle(selectedMetric.color.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    case .wind:
                        AreaMark(x: .value("Time", hour.date), y: .value("Wind Speed", hour.windSpeed))
                            .foregroundStyle(.linearGradient(colors: [selectedMetric.color.opacity(0.8), selectedMetric.color.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                    case .precipitation:
                        BarMark(x: .value("Time", hour.date), y: .value("Rain Chance", hour.pop * 100))
                            .foregroundStyle(selectedMetric.color)
                            .cornerRadius(2)
                    case .optimal:
                        // ✅ CHANGED: Pass idealTemp to comfort function
                        AreaMark(x: .value("Time", hour.date), y: .value("Optimal Score", hour.enhancedCyclingComfort(using: viewModel.settings.units, idealTemp: viewModel.settings.idealTemperature, uvIndex: hour.uvIndex, aqi: hour.aqi) * 100))
                            .foregroundStyle(.linearGradient(colors: [selectedMetric.color.opacity(0.8), selectedMetric.color.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                    }
                    
                    if let selectedForecast, selectedForecast.id == hour.id {
                        RuleMark(x: .value("Selected", selectedForecast.date))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                            .annotation(position: .top, alignment: .center, spacing: 10) {
                                ScrubbingInfoCard(forecast: selectedForecast)
                                    .environmentObject(viewModel)
                            }
                    }
                }
                .chartXScale(domain: xDomain)

                .chartXScale(domain: xDomain)
                .chartYScale(domain: {
                    switch selectedMetric {
                    case .temperature:
                        let minVal = filteredData.map(\.temp).min() ?? 0
                        let maxVal = max(filteredData.map(\.feelsLike).max() ?? 0, minVal + 10)
                        return (Double(minVal - 5))...(Double(maxVal + 5))
                    case .wind:
                        let maxVal = filteredData.map(\.windSpeed).max() ?? 0
                        return 0...(maxVal * 1.2)
                    case .precipitation:
                        return 0...100
                    case .comfort, .optimal:
                        return 0...100
                    }
                }())


                .frame(height: 250)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        findSelectedHour(at: value.location, proxy: proxy, geometry: geometry)
                                    }
                                    .onEnded { _ in
                                        selectedForecast = nil
                                    }
                            )
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: xAxisStride)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.white.opacity(0.2))
                        if let date = value.as(Date.self) {
                            AxisValueLabel(date.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.white.opacity(0.2))
                        AxisValueLabel()
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .animation(.smooth, value: selectedForecast?.id)
            } else {
                SimpleChartView(data: filteredData, metric: selectedMetric, color: selectedMetric.color)
                    // ✅ CHANGED: Add the missing environmentObject to fix the error
                    .environmentObject(viewModel)
                    .frame(height: 250)
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.2), lineWidth: 1))
    }*/
    // Add this new computed property to your view
    @ViewBuilder
    private var interactiveChart: some View {
        if #available(iOS 16.0, *), !filteredData.isEmpty {
            let xDomain = (filteredData.first?.date ?? Date())...(filteredData.last?.date ?? Date())

            Chart(filteredData, id: \.id) { hour in
                switch selectedMetric {
                case .comfort:
                    AreaMark(x: .value("Time", hour.date), y: .value("Comfort", hour.enhancedCyclingComfort(using: viewModel.settings.units, idealTemp: viewModel.settings.idealTemperature, uvIndex: hour.uvIndex, aqi: hour.aqi) * 100))
                        .foregroundStyle(.linearGradient(colors: [selectedMetric.color.opacity(0.8), selectedMetric.color.opacity(0.2)], startPoint: .top, endPoint: .bottom))

                case .temperature:
                    LineMark(
                        x: .value("Time", hour.date),
                        y: .value("Temperature", hour.temp),
                        series: .value("Type", "Actual") // Add this to define the series
                    )
                    .foregroundStyle(by: .value("Type", "Actual")) // Style by the series value

                    LineMark(
                        x: .value("Time", hour.date),
                        y: .value("Feels Like", hour.feelsLike),
                        series: .value("Type", "Feels Like") // Add this to define the series
                    )
                    .foregroundStyle(by: .value("Type", "Feels Like")) // Style by the series value
                    
                case .wind:
                    AreaMark(x: .value("Time", hour.date), y: .value("Wind Speed", hour.windSpeed))
                        .foregroundStyle(.linearGradient(colors: [selectedMetric.color.opacity(0.8), selectedMetric.color.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                case .precipitation:
                    BarMark(x: .value("Time", hour.date), y: .value("Rain Chance", hour.pop * 100))
                        .foregroundStyle(selectedMetric.color)
                        .cornerRadius(2)
                case .optimal:
                    AreaMark(x: .value("Time", hour.date), y: .value("Optimal Score", hour.enhancedCyclingComfort(using: viewModel.settings.units, idealTemp: viewModel.settings.idealTemperature, uvIndex: hour.uvIndex, aqi: hour.aqi) * 100))
                        .foregroundStyle(.linearGradient(colors: [selectedMetric.color.opacity(0.8), selectedMetric.color.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                }
                
                if let selectedForecast, selectedForecast.id == hour.id {
                    RuleMark(x: .value("Selected", selectedForecast.date))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                        .annotation(position: .top, alignment: .center, spacing: 10) {
                            ScrubbingInfoCard(forecast: selectedForecast)
                                .environmentObject(viewModel)
                        }
                }
            }
            .chartForegroundStyleScale([
                "Actual": selectedMetric.color, // This keeps the actual temp orange
                "Feels Like": .red              // This makes the feels-like temp red
            ])
            .chartLegend(selectedMetric == .temperature ? .automatic : .hidden)
            .chartXScale(domain: xDomain)
            .chartYScale(domain: {
                switch selectedMetric {
                case .temperature:
                    let minVal = filteredData.map(\.temp).min() ?? 0
                    let maxVal = max(filteredData.map(\.feelsLike).max() ?? 0, minVal + 10)
                    return (Double(minVal - 5))...(Double(maxVal + 5))
                case .wind:
                    let maxVal = filteredData.map(\.windSpeed).max() ?? 0
                    return 0...(maxVal * 1.2)
                case .precipitation:
                    return 0...100
                case .comfort, .optimal:
                    return 0...100
                }
            }())
            .frame(height: 250)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    findSelectedHour(at: value.location, proxy: proxy, geometry: geometry)
                                }
                                .onEnded { _ in
                                    selectedForecast = nil
                                }
                        )
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: xAxisStride)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.white.opacity(0.2))
                    if let date = value.as(Date.self) {
                        AxisValueLabel(date.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.2))
                    AxisValueLabel()
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .animation(.smooth, value: selectedForecast?.id)
        } else {
            SimpleChartView(data: filteredData, metric: selectedMetric, color: selectedMetric.color)
                .environmentObject(viewModel)
                .frame(height: 250)
        }
    }
    
    private var mainChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("\(selectedMetric.rawValue) Trends", systemImage: selectedMetric.icon)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            if selectedForecast == nil {
                Text("Tap or drag on the chart to see details")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(height: 60, alignment: .center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            } else {
                Spacer().frame(height: 60)
            }

            // Call the new, separated chart view
            interactiveChart
            comfortScoreExplanation
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.2), lineWidth: 1))
    }
    
    
    
    private func findSelectedHour(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let date: Date = proxy.value(atX: location.x) else { return }
        
        var minDistance: TimeInterval = .infinity
        var closestForecast: HourlyForecast? = nil
        
        for forecast in filteredData {
            let distance = abs(forecast.date.timeIntervalSince(date))
            if distance < minDistance {
                minDistance = distance
                closestForecast = forecast
            }
        }
        
        if selectedForecast?.id != closestForecast?.id {
            selectedForecast = closestForecast
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
    
    private var detailedAnalysis: some View {
        ViewThatFits {
            HStack(alignment: .top, spacing: 16) {
                hourlyDetailsCard
                windAnalysisCard
            }
            VStack(spacing: 16) {
                hourlyDetailsCard
                windAnalysisCard
            }
        }
    }
    
    private var hourlyDetailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Hourly Details", systemImage: "clock.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            LazyVStack(spacing: 8) {
                ForEach(Array(filteredData.enumerated().filter { $0.offset % 2 == 0 }), id: \.element.id) { _, hour in
                    AnalyticsHourlyRow(hour: hour)
                        .environmentObject(viewModel)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var windAnalysisCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Wind Analysis", systemImage: "wind")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            AnalyticsWindCard(hourlyData: filteredData)
                .environmentObject(viewModel)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var smartRecommendations: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Smart Cycling Recommendations", systemImage: "lightbulb.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 1), spacing: 12) {
                AnalyticsRecommendationCard(icon: "star.fill", title: "Optimal Window", description: optimalWindowRecommendation, color: .green)
                AnalyticsRecommendationCard(icon: "map.fill", title: "Route Strategy", description: routeStrategyRecommendation, color: .blue)
                AnalyticsRecommendationCard(icon: "bag.fill", title: "Gear Advice", description: gearAdviceRecommendation, color: .orange)
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Computed Properties for UI
    
    // ✅ CHANGED: Update the helper to be initialized with the idealTemp
    private var analyticsHelper: CyclingAnalyticsHelper {
        CyclingAnalyticsHelper(hourlyData: filteredData, units: viewModel.settings.units, idealTemp: viewModel.settings.idealTemperature)
    }
    
    private var bestHour: HourlyForecast? {
        analyticsHelper.bestHour
    }
    
    private var maxRainChance: Double {
        filteredData.map { $0.pop }.max() ?? 0
    }
    
    private var optimalWindowRecommendation: String {
        if let recommendation = analyticsHelper.recommendations.first(where: { $0.title == "Optimal Window" }) {
            return recommendation.description
        }
        return "Unable to determine optimal cycling window"
    }
    
    private var routeStrategyRecommendation: String {
        let maxWindSpeed = filteredData.map { $0.windSpeed }.max() ?? 0
        let windThreshold: Double = viewModel.settings.units == .metric ? 24.0 : 15.0
        if maxWindSpeed > windThreshold {
            let unit = viewModel.settings.units.speedUnitAbbreviation
            return "High winds expected (\(Int(maxWindSpeed)) \(unit)). Choose sheltered routes or plan shorter rides."
        } else {
            return "Moderate winds. Any route should be comfortable for your planned distance."
        }
    }
    
    private var gearAdviceRecommendation: String {
        let tempRange = filteredData.temperatureRange(using: viewModel.settings.units)
        let coldThreshold: Double = viewModel.settings.units == .metric ? 10.0 : 50.0
        let hotThreshold: Double = viewModel.settings.units == .metric ? 30.0 : 85.0
        
        if tempRange.min < coldThreshold || tempRange.max > hotThreshold {
            return "Temperature extremes expected (\(tempRange.formatted)). Layer appropriately and bring extra fluids."
        } else {
            return "Standard cycling gear should be comfortable throughout your ride."
        }
    }
    
    private var backgroundGradient: LinearGradient {
        LinearGradient(colors: [.blue.opacity(0.8), .indigo.opacity(0.6), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    // Add this new view anywhere inside AnalyticsDashboardView

    @ViewBuilder
    private var comfortScoreExplanation: some View {
        // This view only appears for relevant metrics
        if selectedMetric == .comfort || selectedMetric == .optimal {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                    .padding(.top, 2) // Aligns the icon nicely with the text
                
                Text("The Comfort Score is a proprietary formula based on temperature, wind speed, precipitation probability, visibility, air quality and UV index.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.top, 12)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    
}

// MARK: - Custom Comfort Gauge View

private struct ComfortGauge: View {
    let value: Int // 0-100
    private var percentage: Double { Double(value) / 100.0 }

    var body: some View {
        ZStack {
            Circle().stroke(lineWidth: 8).opacity(0.2).foregroundColor(.gray)
            Circle()
                .trim(from: 0.0, to: min(percentage, 1.0))
                .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                .fill(.green.gradient)
                .rotationEffect(Angle(degrees: 270.0))
            Text("\(value)%")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
        }
        .animation(.smooth, value: value)
    }
}

// MARK: - Scrubbing Info Card

private struct ScrubbingInfoCard: View {
    let forecast: HourlyForecast
    @EnvironmentObject var viewModel: WeatherViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(forecast.date, format: .dateTime.weekday(.abbreviated).hour())
                .font(.callout.bold())
                .foregroundStyle(.white)
            Divider().background(.white.opacity(0.5))
            HStack(spacing: 8) {
                Image(systemName: "thermometer").foregroundStyle(.orange).frame(width: 16)
                Text(forecast.formattedTemp(using: viewModel.settings.units))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 8) {
                Image(systemName: "thermometer.variable").foregroundStyle(.red).frame(width: 16)
                Text("Feels \(forecast.formattedFeelsLike(using: viewModel.settings.units))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 8) {
                Image(systemName: "wind").foregroundStyle(.cyan).frame(width: 16)
                Image(systemName: "arrow.up")
                    .font(.caption2)
                    .rotationEffect(.degrees(Double(forecast.windDeg) + 180))
                Text(forecast.formattedWindSpeed(using: viewModel.settings.units))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 8) {
                Image(systemName: "drop.fill").foregroundStyle(.blue).frame(width: 16)
                Text("\(Int(forecast.pop * 100))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(12)
        .frame(minWidth: 120)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Supporting Views

struct AnalyticsStatCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.3), lineWidth: 1))
    }
}

struct AnalyticsHourlyRow: View {
    let hour: HourlyForecast
    @EnvironmentObject var viewModel: WeatherViewModel
    
    private func formattedDateTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E h a" // e.g., "Mon 7 PM"
        return formatter.string(from: date)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Text(formattedDateTime(from: hour.date))
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 67, alignment: .leading)
            Image(systemName: hour.iconName)
                .font(.caption)
                .symbolRenderingMode(.multicolor)
                .frame(width: 18)
            Text(hour.formattedTemp(using: viewModel.settings.units))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 50, alignment: .trailing)
            HStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.caption2)
                    .rotationEffect(.degrees(Double(hour.windDeg) + 180))
                Text(hour.formattedWindSpeed(using: viewModel.settings.units))
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(.cyan)
            .frame(width: 55)
            Spacer()
            // ✅ CHANGED: Pass idealTemp to both comfort calculations
            let comfort = Int(hour.enhancedCyclingComfort(using: viewModel.settings.units, idealTemp: viewModel.settings.idealTemperature, uvIndex: hour.uvIndex, aqi: hour.aqi) * 100)
            let comfortColor = hour.comfortColor(using: viewModel.settings.units, idealTemp: viewModel.settings.idealTemperature)

            Text("\(comfort)%")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(comfortColor.opacity(0.3), in: Capsule())
                .foregroundStyle(comfortColor)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AnalyticsWindCard: View {
    let hourlyData: [HourlyForecast]
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var avgWindSpeed: Int {
        guard !hourlyData.isEmpty else { return 0 }
        let avgSpeed = hourlyData.reduce(0) { $0 + $1.windSpeed } / Double(hourlyData.count)
        return Int(viewModel.settings.units == .metric ? avgSpeed * 1.60934 : avgSpeed)
    }
    
    var primaryDirection: String {
        guard !hourlyData.isEmpty else { return "N" }
        let avgDirection = hourlyData.reduce(0) { $0 + Double($1.windDeg) } / Double(hourlyData.count)
        return getWindDirection(degrees: avgDirection)
    }
    
    var windDistribution: [(range: String, count: Int, color: Color)] {
        let isMetric = viewModel.settings.units == .metric
        let light = isMetric ? "0-16 kph" : "0-10 mph"
        let moderate = isMetric ? "17-32 kph" : "11-20 mph"
        let strong = isMetric ? "32+ kph" : "20+ mph"
        
        let lightThreshold: Double = isMetric ? 16.0 : 10.0
        let moderateThreshold: Double = isMetric ? 32.0 : 20.0
        
        return [
            (range: light, count: hourlyData.filter {
                let speed = isMetric ? $0.windSpeed * 1.60934 : $0.windSpeed
                return speed <= lightThreshold
            }.count, color: .green),
            (range: moderate, count: hourlyData.filter {
                let speed = isMetric ? $0.windSpeed * 1.60934 : $0.windSpeed
                return speed > lightThreshold && speed <= moderateThreshold
            }.count, color: .yellow),
            (range: strong, count: hourlyData.filter {
                let speed = isMetric ? $0.windSpeed * 1.60934 : $0.windSpeed
                return speed > moderateThreshold
            }.count, color: .red)
        ]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Average Speed")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("\(avgWindSpeed) \(viewModel.settings.units.speedUnitAbbreviation)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Primary Direction")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(primaryDirection)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Speed Distribution")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                ForEach(windDistribution, id: \.range) { item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 8, height: 8)
                        Text(item.range)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(item.count)h")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }
    
    private func getWindDirection(degrees: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees + 11.25) / 22.5) % 16
        return directions[index]
    }
}

struct AnalyticsRecommendationCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
        }
        .padding(16)
        .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.4), lineWidth: 1))
    }
}

struct SimpleChartView: View {
    let data: [HourlyForecast]
    let metric: AnalyticsDashboardView.AnalyticMetric
    let color: Color
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    Path { path in
                        let y = geometry.size.height * CGFloat(index) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                    .stroke(.white.opacity(0.1), lineWidth: 1)
                }
                let values = getChartValues()
                if !values.isEmpty {
                    Path { path in
                        let maxValue = values.max() ?? 1
                        let minValue = values.min() ?? 0
                        let range = maxValue - minValue
                        
                        for (index, value) in values.enumerated() {
                            let x = geometry.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                            let normalizedValue = range > 0 ? (value - minValue) / range : 0.5
                            let y = geometry.size.height * (1 - normalizedValue)
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(color, lineWidth: 3)
                    
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        let maxValue = values.max() ?? 1
                        let minValue = values.min() ?? 0
                        let range = maxValue - minValue
                        
                        let x = geometry.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                        let normalizedValue = range > 0 ? (value - minValue) / range : 0.5
                        let y = geometry.size.height * (1 - normalizedValue)
                        
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                            .position(x: x, y: y)
                    }
                }
            }
        }
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private func getChartValues() -> [Double] {
        switch metric {
        case .comfort, .optimal:
            // ✅ CHANGED: Pass idealTemp to comfort function
            return data.map { $0.enhancedCyclingComfort(using: viewModel.settings.units, idealTemp: viewModel.settings.idealTemperature, uvIndex: $0.uvIndex, aqi: $0.aqi) * 100 }
        case .temperature:
            return data.map { $0.temp }
        case .wind:
            return data.map { $0.windSpeed }
        case .precipitation:
            return data.map { $0.pop * 100 }
        }
    }
}
