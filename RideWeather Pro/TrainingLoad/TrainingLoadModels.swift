//
//  TrainingLoadModels.swift
//  RideWeather Pro
//
//  Training Load data models for fitness tracking
//

import Foundation
import SwiftUI

// MARK: - Daily Training Load

struct DailyTrainingLoad: Codable, Identifiable {
    let id: UUID
    let date: Date
    var tss: Double
    var atl: Double?      // Acute Training Load (fatigue)
    var ctl: Double?      // Chronic Training Load (fitness)
    var tsb: Double?      // Training Stress Balance (form)
    var rideCount: Int
    var totalDistance: Double  // meters
    var totalDuration: TimeInterval  // seconds
    
    init(
        id: UUID = UUID(),
        date: Date,
        tss: Double = 0,
        atl: Double? = nil,
        ctl: Double? = nil,
        tsb: Double? = nil,
        rideCount: Int = 0,
        totalDistance: Double = 0,
        totalDuration: TimeInterval = 0
    ) {
        self.id = id
        self.date = date
        self.tss = tss
        self.atl = atl
        self.ctl = ctl
        self.tsb = tsb
        self.rideCount = rideCount
        self.totalDistance = totalDistance
        self.totalDuration = totalDuration
    }
    
    var formStatus: FormStatus {
        guard let tsb = tsb else { return .unknown }
        
        switch tsb {
        case ..<(-30): return .veryFatigued
        case -30..<(-10): return .fatigued
        case -10...5: return .neutral
        case 5..<15: return .fresh
        default: return .veryFresh
        }
    }
    
    enum FormStatus: String {
        case veryFatigued = "Very Fatigued"
        case fatigued = "Fatigued"
        case neutral = "Neutral"
        case fresh = "Fresh"
        case veryFresh = "Very Fresh"
        case unknown = "Unknown"
        
        var color: Color {
            switch self {
            case .veryFatigued: return .red
            case .fatigued: return .orange
            case .neutral: return .blue
            case .fresh: return .green
            case .veryFresh: return .mint
            case .unknown: return .gray
            }
        }
        
        var emoji: String {
            switch self {
            case .veryFatigued: return "🔴"
            case .fatigued: return "🟠"
            case .neutral: return "🔵"
            case .fresh: return "🟢"
            case .veryFresh: return "🟢✨"
            case .unknown: return "⚪️"
            }
        }
    }
}

// MARK: - Training Load Summary

struct TrainingLoadSummary {
    let currentATL: Double
    let currentCTL: Double
    let currentTSB: Double
    let weeklyTSS: Double
    let rampRate: Double  // CTL change per week
    let formStatus: DailyTrainingLoad.FormStatus
    let recommendation: String
    
    var isSafeRampRate: Bool {
        abs(rampRate) <= 8.0  // Safe range: -8 to +8 TSS/week
    }
    
    var rampRateStatus: RampRateStatus {
        switch rampRate {
        case ..<(-8): return .decreasingTooFast
        case -8..<(-3): return .tapering
        case -3...3: return .maintaining
        case 3...8: return .building
        default: return .buildingTooFast
        }
    }
    
    enum RampRateStatus: String {
        case decreasingTooFast = "Detraining"
        case tapering = "Tapering"
        case maintaining = "Maintaining"
        case building = "Building Safely"
        case buildingTooFast = "Building Too Fast"
        
        var color: Color {
            switch self {
            case .decreasingTooFast: return .red
            case .tapering: return .blue
            case .maintaining: return .green
            case .building: return .green
            case .buildingTooFast: return .orange
            }
        }
    }
}

// MARK: - Training Load Period

struct TrainingLoadPeriod {
    let days: Int
    let name: String
    
    static let week = TrainingLoadPeriod(days: 7, name: "Week")
    static let twoWeeks = TrainingLoadPeriod(days: 14, name: "2 Weeks")
    static let month = TrainingLoadPeriod(days: 30, name: "Month")
    static let threeMonths = TrainingLoadPeriod(days: 90, name: "3 Months")
    static let sixMonths = TrainingLoadPeriod(days: 180, name: "6 Months")
    static let year = TrainingLoadPeriod(days: 365, name: "Year")
    
    static let allPeriods: [TrainingLoadPeriod] = [
        .week, .twoWeeks, .month, .threeMonths, .sixMonths, .year
    ]
}

// MARK: - Training Load Insight

struct TrainingLoadInsight: Identifiable {
    let id = UUID()
    let priority: Priority
    let title: String
    let message: String
    let recommendation: String
    let icon: String
    
    enum Priority {
        case critical, warning, info, success
        
        var color: Color {
            switch self {
            case .critical: return .red
            case .warning: return .orange
            case .info: return .blue
            case .success: return .green
            }
        }
    }
}
