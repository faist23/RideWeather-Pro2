//
//  StepsDetailView.swift
//  RideWeatherWatch Watch App
//
//  Updated to fetch steps independently from HealthKit
//

import WidgetKit
import SwiftUI
import HealthKit

struct StepsDetailView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    @State private var todaySteps: Int = 0
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // HEADER
                Text("DAILY ACTIVITY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                } else {
                    // MAIN STEP COUNT
                    VStack(spacing: 4) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 32))
                            .foregroundStyle(.green)
                        
                        Text("\(todaySteps)")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                        
                        Text("steps today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                    
                    // ACTIVITY METRICS (from synced data if available)
                    if let wellness = session.currentWellness {
                        VStack(spacing: 8) {
                            if let activeEnergy = wellness.activeEnergyBurned {
                                DetailRow(
                                    icon: "flame.fill",
                                    label: "Active Calories",
                                    value: "\(Int(activeEnergy)) cal",
                                    color: .red
                                )
                            }
                            
                            if let score = wellness.activityScore {
                                DetailRow(
                                    icon: "chart.bar.fill",
                                    label: "Activity Score",
                                    value: "\(Int(score))",
                                    color: .green
                                )
                            }
                            
                            if let sleep = wellness.totalSleep {
                                let hours = sleep / 3600
                                DetailRow(
                                    icon: "bed.double.fill",
                                    label: "Last Night's Sleep",
                                    value: String(format: "%.1fh", hours),
                                    color: .blue
                                )
                            }
                            
                            if let rhr = wellness.restingHeartRate {
                                DetailRow(
                                    icon: "heart.fill",
                                    label: "Resting Heart Rate",
                                    value: "\(rhr) bpm",
                                    color: .pink
                                )
                            }
                        }
                    }
                    
                    // MOVEMENT INSIGHT
                    VStack(spacing: 6) {
                        Text("TODAY'S MOVEMENT")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        
                        Text(activityAdvice(steps: todaySteps))
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
        }
        .containerBackground(.green.gradient, for: .navigation)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadSteps()
        }
        .onDisappear {
            refreshWidgetData()
        }
    }
    
    private func loadSteps() {
        print("📊 Loading steps for StepsDetailView")
        
        Task {
            let steps = await fetchTodaySteps()
            await MainActor.run {
                self.todaySteps = steps
                self.isLoading = false
                print("📊 Loaded \(steps) steps")
                
                // Save to widget storage immediately
                WatchAppGroupManager.shared.saveSteps(steps)
            }
        }
    }
    
    private func fetchTodaySteps() async -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return 0
        }
        
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
                let steps = Int(sum.doubleValue(for: HKUnit.count()))
                continuation.resume(returning: steps)
            }
            healthStore.execute(query)
        }
    }
    
    private func refreshWidgetData() {
        // Save latest steps to widget storage
        WatchAppGroupManager.shared.saveSteps(todaySteps)
        
        // Force all widgets to reload their timelines
        WidgetCenter.shared.reloadAllTimelines()
        print("🔄 Triggered widget timeline reload")
    }
    
    private func activityAdvice(steps: Int) -> String {
        switch steps {
        case 0..<3000:
            return "Light activity day - consider a short walk"
        case 3000..<7000:
            return "Moderate activity - you're moving well"
        case 7000..<10000:
            return "Great job! Almost at 10k steps"
        case 10000..<15000:
            return "Excellent activity level today!"
        default:
            return "Outstanding! You're crushing it today!"
        }
    }
}

// MARK: - Shared Detail Row Component

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
