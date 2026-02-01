//
//  DailyWellnessMetrics.swift
//  RideWeather Pro
//
//  Wellness metrics from Apple Health (non-workout data)
//

import Foundation

/// Daily wellness metrics from Apple Health
/// These complement training load by tracking overall health and recovery
struct DailyWellnessMetrics: Identifiable, Codable {
    let id: UUID
    let date: Date
    
    // MARK: - Daily Activity (Non-Workout)
    var steps: Int?
    var activeEnergyBurned: Double? // kcal
    var basalEnergyBurned: Double? // kcal (resting metabolism)
    var standHours: Int?
    var exerciseMinutes: Int? // Apple Watch "Exercise" ring
    var restingHeartRate: Int? // bpm
    var distance: Double? // meters (walking + running)
    
    // MARK: - Sleep Quality (Beyond Duration)
    var sleepDeep: TimeInterval?
    var sleepREM: TimeInterval?
    var sleepCore: TimeInterval?
    var sleepAwake: TimeInterval?
    var sleepUnspecified: TimeInterval?
    var sleepEfficiency: Double? // Computed: (Deep+REM+Core)/TotalInBed
    
    // MARK: - Body Metrics
    var bodyMass: Double? // kg
    var bodyFatPercentage: Double?
    var leanBodyMass: Double? // kg
    
    // MARK: - Respiratory & Oxygen
    var respiratoryRate: Double? // breaths/min
    var oxygenSaturation: Double? // %
    
    init(
        id: UUID = UUID(),
        date: Date,
        steps: Int? = nil,
        activeEnergyBurned: Double? = nil,
        basalEnergyBurned: Double? = nil,
        standHours: Int? = nil,
        exerciseMinutes: Int? = nil,
        restingHeartRate: Int? = nil,
        distance: Double? = nil,
        sleepDeep: TimeInterval? = nil,
        sleepREM: TimeInterval? = nil,
        sleepCore: TimeInterval? = nil,
        sleepAwake: TimeInterval? = nil,
        sleepUnspecified: TimeInterval? = nil,
        bodyMass: Double? = nil,
        bodyFatPercentage: Double? = nil,
        leanBodyMass: Double? = nil,
        respiratoryRate: Double? = nil,
        oxygenSaturation: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.steps = steps
        self.activeEnergyBurned = activeEnergyBurned
        self.basalEnergyBurned = basalEnergyBurned
        self.standHours = standHours
        self.exerciseMinutes = exerciseMinutes
        self.restingHeartRate = restingHeartRate
        self.distance = distance
        self.sleepDeep = sleepDeep
        self.sleepREM = sleepREM
        self.sleepCore = sleepCore
        self.sleepAwake = sleepAwake
        self.sleepUnspecified = sleepUnspecified
        self.bodyMass = bodyMass
        self.bodyFatPercentage = bodyFatPercentage
        self.leanBodyMass = leanBodyMass
        self.respiratoryRate = respiratoryRate
        self.oxygenSaturation = oxygenSaturation
    }
    
    // MARK: - Computed Properties
    
    /// Total sleep time (all stages except awake)
    var totalSleep: TimeInterval? {
        let components = [sleepDeep, sleepREM, sleepCore, sleepUnspecified].compactMap { $0 }
        guard !components.isEmpty else { return nil }
        return components.reduce(0, +)
    }
    
    /// Total time in bed (including awake time)
    var totalTimeInBed: TimeInterval? {
        let components = [sleepDeep, sleepREM, sleepCore, sleepAwake, sleepUnspecified].compactMap { $0 }
        guard !components.isEmpty else { return nil }
        return components.reduce(0, +)
    }
    
    /// Sleep efficiency percentage (0-100)
    var computedSleepEfficiency: Double? {
        guard let totalSleep = totalSleep,
              let totalInBed = totalTimeInBed,
              totalInBed > 0 else { return nil }
        return (totalSleep / totalInBed) * 100
    }
    
    /// Total daily energy expenditure
    var totalEnergyBurned: Double? {
        guard let active = activeEnergyBurned,
              let basal = basalEnergyBurned else { return nil }
        return active + basal
    }
    
    /// Activity level score (0-100)
    var activityScore: Int? {
        guard let steps = steps else { return nil }
        
        // Target: 8,000 steps = 100 score
        let stepScore = min(100, Int((Double(steps) / 8000.0) * 100))
        
        return stepScore
    }
    
    /// Recovery quality score (0-100) based on sleep
    var sleepQualityScore: Int? {
        guard let deep = sleepDeep,
              let rem = sleepREM,
              let efficiency = computedSleepEfficiency else { return nil }
        
        // Ideal: 1.5h deep, 1.5h REM, 90% efficiency
        let deepScore = min(100, (deep / (1.5 * 3600)) * 100)
        let remScore = min(100, (rem / (1.5 * 3600)) * 100)
        let efficiencyScore = efficiency
        
        return Int((deepScore + remScore + efficiencyScore) / 3)
    }
}

// MARK: - Wellness Summary

/// Aggregated wellness metrics over a period
struct  WellnessSummary: Codable {
    let period: String // e.g., "Last 7 Days"
    let metrics: [DailyWellnessMetrics]
    
    // MARK: - Averages
    
    var averageSteps: Double? {
        let values = metrics.compactMap { $0.steps }.map { Double($0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    
    var averageSleepHours: Double? {
        let values = metrics.compactMap { $0.totalSleep }
        guard !values.isEmpty else { return nil }
        return (values.reduce(0, +) / Double(values.count)) / 3600
    }
    
    var averageSleepEfficiency: Double? {
        let values = metrics.compactMap { $0.computedSleepEfficiency }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    
    var averageActivityScore: Double? {
        let values = metrics.compactMap { $0.activityScore }.map { Double($0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    
    // MARK: - Trends
    
    /// Activity trend: positive = improving, negative = declining
    var activityTrend: Double? {
        guard metrics.count >= 3 else { return nil }
        
        let recent = metrics.suffix(3).compactMap { $0.activityScore }.map { Double($0) }
        let previous = metrics.prefix(metrics.count - 3).suffix(3).compactMap { $0.activityScore }.map { Double($0) }
        
        guard !recent.isEmpty && !previous.isEmpty else { return nil }
        
        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let previousAvg = previous.reduce(0, +) / Double(previous.count)
        
        return recentAvg - previousAvg
    }
    
    /// Sleep debt in hours for the specific period (negative = sleep deficit)
    var sleepDebt: Double? {
        // 1. We limit the calculation to the last 7 entries in the provided metrics
        let recentMetrics = metrics.suffix(7)
        let values = recentMetrics.compactMap { $0.totalSleep }
        
        guard !values.isEmpty else { return nil }
        
        let targetSleep: TimeInterval = 8 * 3600 // 8 hours target
        let totalActual = values.reduce(0, +)
        
        // 2. We multiply the target by the number of days actually present in the last 7
        let totalTarget = targetSleep * Double(values.count)
        
        return (totalActual - totalTarget) / 3600 // Convert to hours
    }
    
    // MARK: - Insights
    
    func generateInsights() -> [WellnessInsight] {
        var insights: [WellnessInsight] = []
        
        // Sleep Debt Warning
        if let debt = sleepDebt, debt < -5 {
            insights.append(WellnessInsight(
                type: .sleepDebt,
                severity: debt < -10 ? .high : .medium,
                message: "You're \(abs(Int(debt))) hours behind on sleep this week",
                recommendation: "Prioritize 8+ hours tonight to support recovery"
            ))
        }
        
        // Low Activity Warning
        if let avgSteps = averageSteps, avgSteps < 5000 {
            insights.append(WellnessInsight(
                type: .lowActivity,
                severity: .medium,
                message: "Daily activity is below recommended levels",
                recommendation: "Add light walks on rest days to improve circulation and recovery"
            ))
        }
        
        // Poor Sleep Efficiency
        if let efficiency = averageSleepEfficiency, efficiency < 85 {
            insights.append(WellnessInsight(
                type: .sleepQuality,
                severity: .medium,
                message: "Sleep efficiency is \(Int(efficiency))% (target: >85%)",
                recommendation: "Reduce screen time before bed and keep room cool"
            ))
        }
        
        // Positive Activity Trend
        if let trend = activityTrend, trend > 10 {
            insights.append(WellnessInsight(
                type: .positiveProgress,
                severity: .info,
                message: "Daily activity is trending up",
                recommendation: "Keep up the good work with consistent movement"
            ))
        }
        
        return insights
    }
}

// MARK: - Wellness Insight

struct WellnessInsight: Identifiable {
    let id = UUID()
    let type: InsightType
    let severity: Severity
    let message: String
    let recommendation: String
    
    enum InsightType {
        case sleepDebt
        case sleepQuality
        case lowActivity
        case highActivity
        case bodyComposition
        case positiveProgress
    }
    
    enum Severity {
        case high, medium, low, info
        
        var color: String {
            switch self {
            case .high: return "red"
            case .medium: return "orange"
            case .low: return "yellow"
            case .info: return "blue"
            }
        }
        
        var icon: String {
            switch self {
            case .high: return "exclamationmark.triangle.fill"
            case .medium: return "exclamationmark.circle.fill"
            case .low: return "info.circle.fill"
            case .info: return "checkmark.circle.fill"
            }
        }
    }
}
