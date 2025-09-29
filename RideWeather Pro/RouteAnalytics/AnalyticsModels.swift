//
//  RouteTimelinePoint.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/18/25.
//


//
//  AnalyticsModels.swift
//  RideWeather Pro
//
//  Data models for route analytics
//

import SwiftUI
import Foundation

// MARK: - Timeline Models

struct RouteTimelinePoint {
    let id: String
    let time: Date
    let distance: Double
    let weather: DisplayWeatherModel
    let milestone: TimelineMilestone
    let description: String
}

enum TimelineMilestone {
    case start, checkpoint, midpoint, end
    
    var icon: String {
        switch self {
        case .start: return "play.circle.fill"
        case .checkpoint: return "checkmark.circle.fill"
        case .midpoint: return "circle.lefthalf.striped.horizontal"
        case .end: return "flag.checkered.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .start: return .green
        case .checkpoint: return .blue
        case .midpoint: return .orange
        case .end: return .red
        }
    }
}

// MARK: - Segment Models

struct RouteSegment {
    let id: String
    let number: Int
    let startDistance: Double
    let endDistance: Double
    let startTime: Date
    let endTime: Date
    let weatherPoints: [RouteWeatherPoint]
    let analysis: SegmentWeatherAnalysis
    
    var distance: Double {
        endDistance - startDistance
    }
    
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    var durationFormatted: String {
        let totalMinutes = Int(duration / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

struct SegmentWeatherAnalysis {
    let averageTemp: Double
    let tempRange: (min: Double, max: Double)
    let averageWind: Double
    let maxWind: Double
    let averageHumidity: Double
    let dominantCondition: String
    let riskLevel: RiskLevel
}

enum RiskLevel: Int, CaseIterable {
    case low = 1
    case moderate = 2
    case high = 3
    
    var color: Color {
        switch self {
        case .low: return .green
        case .moderate: return .orange
        case .high: return .red
        }
    }
    
    var label: String {
        switch self {
        case .low: return "Low Risk"
        case .moderate: return "Moderate Risk"
        case .high: return "High Risk"
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .low: return .green.opacity(0.1)
        case .moderate: return .orange.opacity(0.1)
        case .high: return .red.opacity(0.1)
        }
    }
}

// MARK: - Insight Models

struct WeatherInsight {
    let id: String
    let title: String
    let message: String
    let recommendation: String
    let priority: InsightPriority
    let icon: String
}

enum InsightPriority: Int, CaseIterable {
    case moderate = 1
    case important = 2
    case critical = 3
    
    var color: Color {
        switch self {
        case .moderate: return .blue
        case .important: return .orange
        case .critical: return .red
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .moderate: return .blue.opacity(0.15)
        case .important: return .orange.opacity(0.15)
        case .critical: return .red.opacity(0.15)
        }
    }
    
    var label: String {
        switch self {
        case .moderate: return "MODERATE"
        case .important: return "IMPORTANT"
        case .critical: return "CRITICAL"
        }
    }
}

// MARK: - Alternative Start Time Models

struct AlternativeStartTime {
    let id: String
    let startTime: Date
    let improvement: Int
    let primaryBenefit: String
    let weatherScore: Double
}

// MARK: - Summary Models

struct AnalyticsSummary {
    let totalDistance: Double
    let estimatedDuration: String
    let temperatureRange: String
    let maxWindSpeed: Double
    let rainRisk: Double
    let criticalInsightCount: Int
    let overallRiskLevel: RiskLevel
    
    var hasWeatherConcerns: Bool {
        criticalInsightCount > 0 || overallRiskLevel != .low
    }
    
    var statusMessage: String {
        if !hasWeatherConcerns {
            return "Excellent conditions expected! 🌟"
        } else if criticalInsightCount == 1 {
            return "1 weather insight to review"
        } else {
            return "\(criticalInsightCount) weather insights to review"
        }
    }
}