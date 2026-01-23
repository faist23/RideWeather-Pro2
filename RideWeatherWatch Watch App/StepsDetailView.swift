//
//  StepsDetailView.swift
//  RideWeatherWatch Watch App
//
//  Design: "Cockpit Density" - Steps Left, Activity Metrics Right.
//  Added: "Last Updated" timestamp.
//

import WidgetKit
import SwiftUI
import HealthKit

struct StepsDetailView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    @State private var todaySteps: Int = 0
    @State private var isLoading = true
    @State private var lastUpdate: Date = Date()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                
                // --- PRIMARY DASHBOARD ---
                HStack(alignment: .center, spacing: 8) {
                    
                    // LEFT: Steps Count
                    VStack(spacing: -2) {
                        Text("\(todaySteps)")
                            .font(.system(size: 42, weight: .black, design: .rounded)) // Slightly smaller to fit 5 digits
                            .foregroundStyle(.green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .shadow(color: .green.opacity(0.3), radius: 4, x: 0, y: 2)
                        
                        Text("STEPS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // RIGHT: Activity Metrics
                    VStack(alignment: .leading, spacing: 6) {
                        
                        // Active Calories (from Wellness sync)
                        if let wellness = session.currentWellness,
                           let activeEnergy = wellness.activeEnergyBurned {
                            CompactMetricRow(
                                icon: "flame.fill",
                                value: "\(Int(activeEnergy))",
                                unit: "cal",
                                color: .red
                            )
                        } else {
                            // Placeholder if no sync yet
                            CompactMetricRow(
                                icon: "flame",
                                value: "--",
                                unit: "cal",
                                color: .gray
                            )
                        }
                        
                        // Activity Score
                        if let wellness = session.currentWellness,
                           let score = wellness.activityScore {
                            CompactMetricRow(
                                icon: "chart.bar.fill",
                                value: "\(Int(score))",
                                unit: "score",
                                color: scoreColor(Int(score))
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
                
                /*                // --- PROGRESS BAR ---
                 // Visual goal (assuming 10k target for visualization)
                 Capsule()
                 .fill(Color.gray.opacity(0.3))
                 .frame(height: 4)
                 .overlay(alignment: .leading) {
                 Capsule()
                 .fill(Color.green)
                 .frame(width: min(1.0, CGFloat(todaySteps) / 10000.0) * 100 + 40) // Dynamic visual
                 }
                 .padding(.vertical, 4)
                 */
                // --- ADVICE ---
                VStack(spacing: 2) {
                    Text(activityTitle(steps: todaySteps).uppercased())
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.green)
                    
                    Text(activityAdvice(steps: todaySteps))
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // --- FOOTER: UPDATED TIME ---
                Text("Updated: \(lastUpdate.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal)
        }
        .containerBackground(.green.gradient, for: .tabView)
        .containerBackground(.green.gradient, for: .navigation) // Fixes Deep Links
        .onAppear {
            loadSteps()
        }
        .onDisappear {
            refreshWidgetData()
        }
    }
    
    // MARK: - Logic
    
    private func loadSteps() {
        Task {
            let steps = await fetchTodaySteps()
            await MainActor.run {
                self.todaySteps = steps
                self.isLoading = false
                self.lastUpdate = Date()
                
                // Save to widget storage
                WatchAppGroupManager.shared.saveSteps(steps)
            }
        }
    }
    
    private func fetchTodaySteps() async -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let healthStore = HKHealthStore()
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                guard let result = result, let sum = result.sumQuantity() else {
                    continuation.resume(returning: 0)
                    return
                }
                continuation.resume(returning: Int(sum.doubleValue(for: HKUnit.count())))
            }
            healthStore.execute(query)
        }
    }
    
    private func refreshWidgetData() {
        WatchAppGroupManager.shared.saveSteps(todaySteps)
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func activityTitle(steps: Int) -> String {
        switch steps {
        case 0..<3000: return "Get Moving"
        case 3000..<7000: return "Good Start"
        case 7000..<10000: return "Almost There"
        case 10000..<15000: return "Goal Hit"
        default: return "Unstoppable"
        }
    }
    
    private func activityAdvice(steps: Int) -> String {
        switch steps {
        case 0..<3000: return "Consider a short walk to boost circulation."
        case 3000..<7000: return "You're moving well. Keep it up!"
        case 7000..<10000: return "Great job! Closing in on 10k."
        case 10000..<15000: return "Excellent activity level today!"
        default: return "Outstanding daily volume!"
        }
    }
    
    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .yellow }
        return .orange
    }
}
