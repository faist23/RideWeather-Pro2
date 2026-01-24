//
//  StepsDetailView.swift
//  RideWeatherWatch Watch App
//
//  Design: Steps count with Apple Fitness Activity Rings
//

import WidgetKit
import SwiftUI
import HealthKit

struct StepsDetailView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    @State private var todaySteps: Int = 0
    @State private var moveCalories: Double = 0
    @State private var moveGoal: Double = 400
    @State private var exerciseMinutes: Double = 0
    @State private var exerciseGoal: Double = 30
    @State private var standHours: Int = 0
    @State private var standGoal: Int = 12
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
                            .font(.system(size: 42, weight: .black, design: .rounded))
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
                    
                    // RIGHT: Apple Fitness-style Activity Rings
                    // Black background required by Apple guidelines
                    ZStack {
                        // Black circular background
                        Circle()
                            .fill(.black)
                            .frame(width: 72, height: 72)
                        
                        ZStack {
                            // Move (outer) - Tighter spacing
                            ActivityRingView(
                                progress: moveCalories / moveGoal,
                                ringType: .move,
                                lineWidth: 7
                            )
                            .frame(width: 64, height: 64)

                            // Exercise (middle)
                            ActivityRingView(
                                progress: exerciseMinutes / exerciseGoal,
                                ringType: .exercise,
                                lineWidth: 7
                            )
                            .frame(width: 48, height: 48)

                            // Stand (inner)
                            ActivityRingView(
                                progress: Double(standHours) / Double(standGoal),
                                ringType: .stand,
                                lineWidth: 7
                            )
                            .frame(width: 32, height: 32)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
                
                // --- ACTIVITY METRICS ---
                VStack(alignment: .leading, spacing: 6) {
                    // Move
                    HStack {
                        Circle()
                            .fill(Color(red: 250/255, green: 17/255, blue: 79/255))
                            .frame(width: 8, height: 8)
                        Text("Move")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(moveCalories)) / \(Int(moveGoal)) cal")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    
                    // Exercise
                    HStack {
                        Circle()
                            .fill(Color(red: 166/255, green: 255/255, blue: 0/255))
                            .frame(width: 8, height: 8)
                        Text("Exercise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(exerciseMinutes)) / \(Int(exerciseGoal)) min")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    
                    // Stand
                    HStack {
                        Circle()
                            .fill(Color(red: 0/255, green: 255/255, blue: 249/255))
                            .frame(width: 8, height: 8)
                        Text("Stand")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(standHours) / \(standGoal) hrs")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // --- ADVICE ---
                VStack(spacing: 2) {
                    Text(activityTitle().uppercased())
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.green)
                    
                    Text(activityAdvice())
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
        .containerBackground(.green.gradient, for: .navigation)
        .onAppear {
            loadActivityData()
        }
        .onDisappear {
            refreshWidgetData()
        }
    }
    
    // MARK: - Logic
    
    private func loadActivityData() {
        Task {
            // Request permissions first
            await requestHealthKitPermissions()
            
            async let steps = fetchTodaySteps()
            async let move = fetchActivitySummary(.activeEnergyBurned)
            async let exercise = fetchActivitySummary(.appleExerciseTime)
            async let stand = fetchStandHours()
            
            let (stepsValue, moveValue, exerciseValue, standValue) = await (steps, move, exercise, stand)
            
            await MainActor.run {
                self.todaySteps = stepsValue
                self.moveCalories = moveValue.current
                self.moveGoal = moveValue.goal
                self.exerciseMinutes = exerciseValue.current / 60
                self.exerciseGoal = exerciseValue.goal / 60
                self.standHours = standValue
                self.isLoading = false
                self.lastUpdate = Date()
                
                print("📊 Activity Data Loaded:")
                print("   Steps: \(stepsValue)")
                print("   Move: \(Int(moveValue.current))/\(Int(moveValue.goal)) cal")
                print("   Exercise: \(Int(exerciseValue.current/60))/\(Int(exerciseValue.goal/60)) min")
                print("   Stand: \(standValue)/\(standGoal) hrs")
                
                WatchAppGroupManager.shared.saveSteps(stepsValue)
            }
        }
    }
    
    private func requestHealthKitPermissions() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("❌ HealthKit not available")
            return
        }
        
        let healthStore = HKHealthStore()
        
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .appleStandTime)!,
            HKObjectType.activitySummaryType()
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            print("✅ HealthKit permissions requested")
        } catch {
            print("❌ HealthKit authorization failed: \(error)")
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
    
    private func fetchActivitySummary(_ identifier: HKQuantityTypeIdentifier) async -> (current: Double, goal: Double) {
        let healthStore = HKHealthStore()
        let calendar = Calendar.current
        let now = Date()
        
        let predicate = HKQuery.predicateForActivitySummary(with: DateComponents(
            calendar: calendar,
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now),
            day: calendar.component(.day, from: now)
        ))
        
        return await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error = error {
                    print("❌ Activity summary error for \(identifier.rawValue): \(error)")
                    continuation.resume(returning: (0, identifier == .activeEnergyBurned ? 400 : 30))
                    return
                }
                
                guard let summary = summaries?.first else {
                    print("⚠️ No activity summary found for today")
                    continuation.resume(returning: (0, identifier == .activeEnergyBurned ? 400 : 30))
                    return
                }
                
                switch identifier {
                case .activeEnergyBurned:
                    let current = summary.activeEnergyBurned.doubleValue(for: .kilocalorie())
                    let goal = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
                    print("📊 Move: \(Int(current))/\(Int(goal)) cal")
                    continuation.resume(returning: (current, goal))
                case .appleExerciseTime:
                    let current = summary.appleExerciseTime.doubleValue(for: .second())
                    let goal = summary.appleExerciseTimeGoal.doubleValue(for: .second())
                    print("📊 Exercise: \(Int(current/60))/\(Int(goal/60)) min")
                    continuation.resume(returning: (current, goal))
                default:
                    continuation.resume(returning: (0, 0))
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchStandHours() async -> Int {
        let healthStore = HKHealthStore()
        let calendar = Calendar.current
        let now = Date()
        
        let predicate = HKQuery.predicateForActivitySummary(with: DateComponents(
            calendar: calendar,
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now),
            day: calendar.component(.day, from: now)
        ))
        
        return await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error = error {
                    print("❌ Stand hours error: \(error)")
                    continuation.resume(returning: 0)
                    return
                }
                
                guard let summary = summaries?.first else {
                    print("⚠️ No stand hours summary found")
                    continuation.resume(returning: 0)
                    return
                }
                let hours = Int(summary.appleStandHours.doubleValue(for: .count()))
                print("📊 Stand: \(hours)/12 hrs")
                continuation.resume(returning: hours)
            }
            healthStore.execute(query)
        }
    }
    
    private func refreshWidgetData() {
        WatchAppGroupManager.shared.saveSteps(todaySteps)
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func activityTitle() -> String {
        let movePercent = moveCalories / moveGoal
        let exercisePercent = exerciseMinutes / exerciseGoal
        
        if movePercent >= 1.0 && exercisePercent >= 1.0 && standHours >= standGoal {
            return "All Rings Closed!"
        } else if movePercent >= 1.0 {
            return "Move Goal Hit"
        } else if exercisePercent >= 0.8 {
            return "Almost There"
        } else {
            return "Keep Moving"
        }
    }
    
    private func activityAdvice() -> String {
        let movePercent = moveCalories / moveGoal
        let exercisePercent = exerciseMinutes / exerciseGoal
        
        if movePercent >= 1.0 && exercisePercent >= 1.0 && standHours >= standGoal {
            return "Outstanding! All activity goals achieved today."
        } else if movePercent < 0.5 {
            return "Get active to start closing your Move ring."
        } else if exercisePercent < 1.0 {
            return "You're \(Int((1.0 - exercisePercent) * exerciseGoal)) minutes from your Exercise goal."
        } else if standHours < standGoal {
            return "Stand up \(standGoal - standHours) more times to complete Stand goal."
        } else {
            return "Great progress! Keep it up."
        }
    }
}

// MARK: - Ring Type

enum RingType {
    case move
    case exercise
    case stand
}

// MARK: - Activity Ring View

struct ActivityRingView: View {
    let progress: Double
    let ringType: RingType
    let lineWidth: CGFloat

    private var clampedProgress: Double {
        min(max(progress, 0), 2)
    }
    
    // Apple's exact colors from documentation
    private var baseColor: Color {
        switch ringType {
        case .move:
            return Color(red: 250/255, green: 17/255, blue: 79/255)
        case .exercise:
            return Color(red: 166/255, green: 255/255, blue: 0/255)
        case .stand:
            return Color(red: 0/255, green: 255/255, blue: 249/255)
        }
    }

    var body: some View {
        ZStack {
            // Background ring (empty state)
            Circle()
                .stroke(
                    baseColor.opacity(0.25),
                    lineWidth: lineWidth
                )

            // Main progress ring (0-100%)
            Circle()
                .trim(from: 0, to: min(clampedProgress, 1.0))
                .stroke(
                    baseColor,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            // Overflow ring (100%+) - FULL OPACITY for visibility
            if clampedProgress > 1.0 {
                Circle()
                    .trim(from: 0, to: min(clampedProgress - 1.0, 1.0))
                    .stroke(
                        baseColor,  // Same full color, not dimmed
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(
            .timingCurve(0.2, 0.8, 0.2, 1.0, duration: 0.45),
            value: clampedProgress
        )
    }
}
