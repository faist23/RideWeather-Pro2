//
//  WellnessManager.swift
//  RideWeather Pro
//
//  Manages wellness data storage and provides insights
//

import Foundation
import SwiftUI
import Combine

@MainActor
class WellnessManager: ObservableObject {
    static let shared = WellnessManager()
    
    @Published var dailyMetrics: [DailyWellnessMetrics] = []
    @Published var currentSummary: WellnessSummary?
    @Published var lastSyncDate: Date?
    
    private let storage = WellnessStorage.shared
    
    private init() {
        loadMetrics()
        loadSyncDate()
    }
    
    // MARK: - Data Management
    
    func updateMetrics(_ metrics: DailyWellnessMetrics) {
        let calendar = Calendar.current
        
        // Remove existing entry for this day if present
        dailyMetrics.removeAll { calendar.isDate($0.date, inSameDayAs: metrics.date) }
        
        // Add new metrics
        dailyMetrics.append(metrics)
        
        // Sort by date
        dailyMetrics.sort { $0.date < $1.date }
        
        // Keep last 90 days
        let cutoffDate = calendar.date(byAdding: .day, value: -90, to: Date())!
        dailyMetrics.removeAll { $0.date < cutoffDate }
        
        saveMetrics()
        updateSummary()
    }
    
    func updateBulkMetrics(_ metrics: [DailyWellnessMetrics]) {
        for metric in metrics {
            let calendar = Calendar.current
            dailyMetrics.removeAll { calendar.isDate($0.date, inSameDayAs: metric.date) }
            dailyMetrics.append(metric)
        }
        
        dailyMetrics.sort { $0.date < $1.date }
        
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        dailyMetrics.removeAll { $0.date < cutoffDate }
        
        saveMetrics()
        updateSummary()
    }
    
    func updateSummary(days: Int = 7) {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return }
        
        let recentMetrics = dailyMetrics.filter { $0.date >= startDate && $0.date <= endDate }
        
        currentSummary = WellnessSummary(period: "Last \(days) Days", metrics: recentMetrics)
    }
    
    // MARK: - Sync
    
    func syncFromHealthKit(healthManager: HealthKitManager, days: Int = 7) async {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return }
        
        print("🏥 Wellness: Syncing \(days) days from Health...")
        
        let metrics = await healthManager.fetchWellnessMetrics(startDate: startDate, endDate: endDate)
        
        if let last = metrics.last {
            print("🏥 Debug Last Metric: Date=\(last.date), SleepDeep=\(last.sleepDeep ?? 0), SleepREM=\(last.sleepREM ?? 0)")
        } else {
            print("🏥 Debug: No metrics returned from HealthManager")
        }
        
        await MainActor.run {
            updateBulkMetrics(metrics)
            lastSyncDate = Date()
            saveSyncDate()
            print("🏥 Wellness: Synced \(metrics.count) days")
        }
    }
    
    var needsSync: Bool {
        guard let lastSync = lastSyncDate else { return true }
        return Date().timeIntervalSince(lastSync) > 3600 // 1 hour
    }
    
    // MARK: - Insights
    
    func getWellnessInsights() -> [WellnessInsight] {
        guard let summary = currentSummary else { return [] }
        return summary.generateInsights()
    }
    
    /// Combined insights with training load context
    func getCombinedInsights(trainingLoadSummary: TrainingLoadSummary?) -> [CombinedInsight] {
        var insights: [CombinedInsight] = []
        
        guard let wellnessSummary = currentSummary else { return insights }
        
        // INSIGHT 1: Recovery Mismatch
        if let trainingLoad = trainingLoadSummary,
           let avgSteps = wellnessSummary.averageSteps {
            
            // High TSB but low activity = not truly recovering
            if trainingLoad.currentTSB > 5 && avgSteps < 5000 {
                insights.append(CombinedInsight(
                    title: "Inactive Recovery Detected",
                    message: "TSB shows you're recovered (+\(Int(trainingLoad.currentTSB))), but you're averaging only \(Int(avgSteps)) steps/day",
                    recommendation: "Add 20-30min easy walks daily. Active recovery improves circulation and speeds healing.",
                    priority: .medium,
                    icon: "figure.walk"
                ))
            }
            
            // Negative TSB + High Activity = overtraining risk
            if trainingLoad.currentTSB < -10 && avgSteps > 12000 {
                insights.append(CombinedInsight(
                    title: "Insufficient Rest",
                    message: "TSB is \(Int(trainingLoad.currentTSB)) and you're walking \(Int(avgSteps)) steps/day—minimal rest is occurring",
                    recommendation: "Consider a complete rest day with <5000 steps to allow deep recovery.",
                    priority: .high,
                    icon: "bed.double.fill"
                ))
            }
        }
        
        // INSIGHT 2: Sleep Debt Impact
        if let sleepDebt = wellnessSummary.sleepDebt,
           let trainingLoad = trainingLoadSummary,
           sleepDebt < -3 {
            
            insights.append(CombinedInsight(
                title: "Sleep Debt Accumulating",
                message: "You're \(abs(Int(sleepDebt))) hours behind on sleep with a TSB of \(String(format: "%.1f", trainingLoad.currentTSB))",
                recommendation: sleepDebt < -5 ? "Consider reducing training volume by 20% until sleep normalizes" : "Prioritize 8+ hours tonight",
                priority: sleepDebt < -5 ? .high : .medium,
                icon: "moon.zzz.fill"
            ))
        }
        
        // INSIGHT 3: Positive Recovery Pattern
        if let avgSleep = wellnessSummary.averageSleepHours,
           let avgSteps = wellnessSummary.averageSteps,
           let trainingLoad = trainingLoadSummary,
           avgSleep >= 7.5 && avgSteps >= 6000 && trainingLoad.currentTSB > 0 {
            
            insights.append(CombinedInsight(
                title: "Optimal Recovery Window",
                message: "Great sleep (\(String(format: "%.1f", avgSleep))h), good activity (\(Int(avgSteps)) steps), and positive form",
                recommendation: "Perfect time for a breakthrough workout—your body is ready!",
                priority: .info,
                icon: "checkmark.circle.fill"
            ))
        }
        
        // INSIGHT 4: Body Composition + Training Load
        if let latest = dailyMetrics.last,
           let bodyFat = latest.bodyFatPercentage,
           let trainingLoad = trainingLoadSummary {
            
            if trainingLoad.weeklyTSS > 500 && bodyFat > 15 {
                insights.append(CombinedInsight(
                    title: "High Volume Training",
                    message: "Logging \(Int(trainingLoad.weeklyTSS)) TSS/week with current body composition",
                    recommendation: "Ensure adequate fueling (300-400 cal/hr on rides >2hrs) to support training volume.",
                    priority: .low,
                    icon: "chart.bar.fill"
                ))
            }
        }
        
        return insights
    }
    
    // MARK: - Persistence
    
    private func saveMetrics() {
        storage.saveMetrics(dailyMetrics)
    }
    
    private func loadMetrics() {
        dailyMetrics = storage.loadMetrics()
        updateSummary()
    }
    
    private func saveSyncDate() {
        if let date = lastSyncDate {
            storage.saveSyncDate(date)
        }
    }
    
    private func loadSyncDate() {
        lastSyncDate = storage.loadSyncDate()
    }
    
    func clearAll() {
        dailyMetrics = []
        currentSummary = nil
        lastSyncDate = nil
        storage.clearAll()
        
        // Clean up any remaining UserDefaults keys
        UserDefaults.standard.removeObject(forKey: "lastWellnessSyncDate")
        
        print("🗑️ Wellness: Cleared all data")
    }
    
    // MARK: - Statistics
    
    func getStorageInfo() -> String {
        let count = dailyMetrics.count
        let size = storage.getStorageSizeFormatted()
        return "\(count) days (\(size))"
    }
}

// MARK: - Combined Insight Model

struct CombinedInsight: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let recommendation: String
    let priority: Priority
    let icon: String
    
    enum Priority {
        case high, medium, low, info
        
        var color: Color {
            switch self {
            case .high: return .red
            case .medium: return .orange
            case .low: return .yellow
            case .info: return .blue
            }
        }
    }
}
