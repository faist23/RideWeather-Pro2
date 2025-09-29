
//
//  AnalyticsViewComponents.swift
//  RideWeather Pro
//
//  Reusable view components for analytics dashboard
//

import SwiftUI

// MARK: - Critical Insights Section

struct CriticalInsightsSection: View {
    let insights: [WeatherInsight]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Weather Insights", systemImage: "lightbulb.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            
            if insights.isEmpty {
                ExcellentConditionsCard()
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(insights, id: \.id) { insight in
                        WeatherInsightCard(insight: insight)
                    }
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct ExcellentConditionsCard: View {
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Excellent Conditions")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                
                Text("No weather concerns for your planned route!")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            
            Spacer()
        }
        .padding(16)
        .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct WeatherInsightCard: View {
    let insight: WeatherInsight
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: insight.icon)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(insight.priority.color)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(insight.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Text(insight.priority.label)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(insight.priority.color.opacity(0.3), in: Capsule())
                        .foregroundStyle(insight.priority.color)
                }
                
                Text(insight.message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                
                Text("💡 \(insight.recommendation)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.yellow)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(insight.priority.backgroundColor, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(insight.priority.color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Timeline Components

struct TimelinePointView: View {
    let point: RouteTimelinePoint
    let isFirst: Bool
    let isLast: Bool
    let units: UnitSystem
    
    private var speedUnit: String {
        units == .metric ? "kph" : "mph"
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Timeline indicator
            VStack(spacing: 0) {
                if !isFirst {
                    Rectangle()
                        .fill(.white.opacity(0.3))
                        .frame(width: 2, height: 20)
                }
                
                Image(systemName: point.milestone.icon)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(point.milestone.color)
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.1), in: Circle())
                
                if !isLast {
                    Rectangle()
                        .fill(.white.opacity(0.3))
                        .frame(width: 2, height: 20)
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.time.formatted(date: .omitted, time: .shortened))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        
                        Text(point.description)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Image(systemName: point.weather.iconName)
                            .font(.title2)
                            .symbolRenderingMode(.multicolor)
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(point.weather.temp))°")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                            
                            Text("\(Int(point.weather.windSpeed)) \(speedUnit)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                
                if point.distance > 0 {
                    Text("Distance: \(point.distance.formatted(.number.precision(.fractionLength(1)))) \(units == .metric ? "km" : "mi")")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.bottom, isLast ? 0 : 8)
        }
    }
}

// MARK: - Segment Components

struct RouteSegmentCard: View {
    let segment: RouteSegment
    let units: UnitSystem
    
    private var speedUnit: String {
        units == .metric ? "kph" : "mph"
    }
    
    private var distanceUnit: String {
        units == .metric ? "km" : "mi"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Segment \(segment.number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.8), in: Capsule())
                
                Text("\(segment.startDistance.formatted(.number.precision(.fractionLength(1)))) - \(segment.endDistance.formatted(.number.precision(.fractionLength(1)))) \(distanceUnit)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text(segment.analysis.riskLevel.label)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(segment.analysis.riskLevel.color.opacity(0.3), in: Capsule())
                    .foregroundStyle(segment.analysis.riskLevel.color)
            }
            
            // Time and duration
            HStack {
                Text("\(segment.startTime.formatted(date: .omitted, time: .shortened)) - \(segment.endTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                
                Text("• \(segment.durationFormatted)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                
                Text("• \(segment.distance.formatted(.number.precision(.fractionLength(1)))) \(distanceUnit)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                
                Spacer()
            }
            
            // Weather details
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                SegmentWeatherDetail(
                    icon: "thermometer",
                    label: "Temperature",
                    value: "\(Int(segment.analysis.averageTemp))°",
                    detail: "\(Int(segment.analysis.tempRange.min))° - \(Int(segment.analysis.tempRange.max))°"
                )
                
                SegmentWeatherDetail(
                    icon: "wind",
                    label: "Wind",
                    value: "\(Int(segment.analysis.maxWind)) \(speedUnit)",
                    detail: "Avg: \(Int(segment.analysis.averageWind)) \(speedUnit)"
                )
                
                SegmentWeatherDetail(
                    icon: "cloud",
                    label: "Conditions",
                    value: segment.analysis.dominantCondition.capitalized,
                    detail: "Humidity: \(Int(segment.analysis.averageHumidity))%"
                )
            }
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SegmentWeatherDetail: View {
    let icon: String
    let label: String
    let value: String
    let detail: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Alternative Start Time Components

struct AlternativeStartTimeCard: View {
    let alternative: AlternativeStartTime
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(alternative.startTime.formatted(date: .abbreviated, time: .shortened))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    
                    Text("Weather Score: \(Int(alternative.weatherScore))/100")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("+\(alternative.improvement)%")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.green)
                    
                    Text("Better")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green.opacity(0.8))
                }
            }
            
            Text(alternative.primaryBenefit)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green.opacity(0.9))
                .lineLimit(2)
        }
        .padding(16)
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.green.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview Card Component

struct RouteAnalyticsPreviewCard: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var showingFullAnalytics = false
    
    private var analytics: RouteAnalyticsEngine {
        RouteAnalyticsEngine(
            weatherPoints: viewModel.weatherDataForRoute,
            rideStartTime: viewModel.rideDate,
            averageSpeed: Double(viewModel.averageSpeedInput) ?? 20.0,
            units: viewModel.settings.units
        )
    }
    
    private var summary: AnalyticsSummary {
        let insights = analytics.generateCriticalInsights()
        return AnalyticsSummary(
            totalDistance: analytics.totalDistance,
            estimatedDuration: analytics.estimatedDuration,
            temperatureRange: analytics.temperatureRangeFormatted,
            maxWindSpeed: analytics.maxWindSpeed,
            rainRisk: analytics.rainRisk,
            criticalInsightCount: insights.count,
            overallRiskLevel: insights.isEmpty ? .low : insights.first?.priority == .critical ? .high : .moderate
        )
    }
    
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Route Weather Analysis")
                        .font(.headline.weight(.semibold))
                    
                    Text(summary.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(summary.hasWeatherConcerns ? .orange : .green)
                }
                
                Spacer()
            }
            
            // Quick stats
            HStack(spacing: 16) {
                PreviewStat(
                    label: "Distance",
                    value: "\(summary.totalDistance.formatted(.number.precision(.fractionLength(1)))) \(viewModel.settings.units == .metric ? "km" : "mi")"
                )
                
                PreviewStat(
                    label: "Duration",
                    value: summary.estimatedDuration
                )
                
                PreviewStat(
                    label: "Temperature",
                    value: summary.temperatureRange
                )
            }
            
            // Preview of top insight if available
            let insights = analytics.generateCriticalInsights()
            if let topInsight = insights.first {
                HStack(spacing: 10) {
                    Image(systemName: topInsight.icon)
                        .font(.subheadline)
                        .foregroundStyle(topInsight.priority.color)
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topInsight.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        
                        Text(topInsight.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                }
                .padding(10)
                .background(topInsight.priority.backgroundColor, in: RoundedRectangle(cornerRadius: 8))
            }
            
            // Action button
            Button {
                showingFullAnalytics = true
            } label: {
                Label("View Detailed Analysis", systemImage: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showingFullAnalytics) {
            RouteAnalyticsDashboardView()
                .environmentObject(viewModel)
        }
    }
}

struct PreviewStat: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
