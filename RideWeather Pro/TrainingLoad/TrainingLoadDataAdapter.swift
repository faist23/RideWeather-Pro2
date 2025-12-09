//
//  TrainingLoadDataAdapter.swift
//  RideWeather Pro
//
//  Unified adapter for syncing training load from multiple sources
//

import Foundation
import HealthKit
import Combine

// MARK: - Data Source Enum

enum DataSource: String, Codable {
    case strava = "Strava"
    case garmin = "Garmin"
    case appleHealth = "Apple Health"
    case wahoo = "Wahoo"
    case manual = "Manual Entry"
}

// MARK: - Protocol

protocol TrainingLoadDataSource {
    func fetchActivities(startDate: Date, endDate: Date) async throws -> [UniversalActivity]
}

// MARK: - Universal Activity Model

struct UniversalActivity {
    let id: String
    let name: String
    let type: ActivityType
    let startDate: Date
    let duration: TimeInterval // seconds
    let distance: Double // meters
    let averagePower: Double? // watts
    let averageHeartRate: Double? // bpm
    let maxHeartRate: Double? // bpm
    let calories: Double? // kcal
    let source: DataSource
    
    enum ActivityType: String {
        case ride = "Ride"
        case virtualRide = "VirtualRide"
        case run = "Run"
        case swim = "Swim"
        case other = "Other"
    }
    
    /// Calculates TSS for this activity
    func calculateTSS(userFTP: Double, userLTHR: Double?) -> Double {
        // 1. If we have power data, use it (most accurate)
        if let avgPower = averagePower, avgPower > 0, userFTP > 0 {
            let hours = duration / 3600.0
            let intensityFactor = avgPower / userFTP
            return hours * intensityFactor * intensityFactor * 100
        }
        
        // 2. If we have heart rate data, estimate from HR
        if let avgHR = averageHeartRate, let lthr = userLTHR, lthr > 0 {
            let hours = duration / 3600.0
            let intensityFactor = avgHR / lthr
            return hours * intensityFactor * intensityFactor * 100
        }
        
        // 3. Fallback: estimate from duration and activity type
        return estimateTSSFromDuration()
    }
    
    private func estimateTSSFromDuration() -> Double {
        let hours = duration / 3600.0
        let estimatedIF: Double
        
        switch type {
        case .ride, .virtualRide:
            estimatedIF = 0.70 // Moderate cycling
        case .run:
            estimatedIF = 0.75 // Moderate run
        case .swim:
            estimatedIF = 0.65 // Moderate swim
        case .other:
            estimatedIF = 0.60 // Conservative estimate
        }
        
        return hours * estimatedIF * estimatedIF * 100
    }
}

// MARK: - Strava Activity Summary Model

struct StravaActivitySummary: Codable {
    let id: Int
    let name: String
    let type: String
    let startDate: Date
    let movingTime: Int
    let elapsedTime: Int
    let distance: Double
    let averageWatts: Double?
    let weightedAverageWatts: Double?
    let sufferScore: Double?
    let averageHeartrate: Double?
    let maxHeartrate: Double?
    let kilojoules: Double?
}

// MARK: - Unified Training Load Sync Manager

@MainActor
class UnifiedTrainingLoadSync: ObservableObject {
    @Published var isSyncing = false
    @Published var syncProgress: Double = 0
    @Published var syncStatus: String = ""
    @Published var lastSyncDate: Date?
    @Published var needsSync: Bool = true
    
    private let trainingLoadManager = TrainingLoadManager.shared
    
    func loadSyncDate() {
        lastSyncDate = UserDefaults.standard.object(forKey: "lastTrainingLoadSync") as? Date
        // Recommend sync if > 1 hour ago
        if let last = lastSyncDate {
            needsSync = Date().timeIntervalSince(last) > 3600
        } else {
            needsSync = true
        }
    }
    
    /// Syncs training load from the currently configured source
    func syncFromConfiguredSource(
        stravaService: StravaService,
        garminService: GarminService,
        healthManager: HealthKitManager,
        userFTP: Double,
        userLTHR: Double?,
        startDate: Date? = nil
    ) async {
        guard !isSyncing else { return }
        isSyncing = true
        
        // 1. Check the Source of Truth (Settings)
                let configSource = DataSourceManager.shared.configuration.trainingLoadSource
                print("🔄 Unified Sync: Using configured source: \(configSource.rawValue)")
                
                do {
                    switch configSource {
                    case .strava:
                        guard stravaService.isAuthenticated else { throw SyncError.notConnected("Strava") }
                        await syncFromStrava(stravaService: stravaService, userFTP: userFTP, userLTHR: userLTHR, startDate: startDate)
                        
                    case .garmin:
                        guard garminService.isAuthenticated else { throw SyncError.notConnected("Garmin") }
                        await syncFromGarmin(garminService: garminService, userFTP: userFTP, userLTHR: userLTHR, startDate: startDate)
                        
                    case .appleHealth:
                        guard healthManager.isAuthorized else { throw SyncError.notConnected("Apple Health") }
                        await syncFromAppleHealth(healthManager: healthManager, userFTP: userFTP, userLTHR: userLTHR, startDate: startDate)
                        
                    case .manual:
                        syncStatus = "Manual mode active"
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                    
                    // Only update success if we didn't throw/fail inside the sub-functions
                    if !syncStatus.contains("failed") {
                        lastSyncDate = Date()
                        UserDefaults.standard.set(lastSyncDate, forKey: "lastTrainingLoadSync")
                        needsSync = false
                    }
                    
                } catch {
                    syncStatus = "Error: \(error.localizedDescription)"
                    print("❌ Unified Sync Error: \(error)")
                }
                
                isSyncing = false
            }
    
    // MARK: - 1. Strava Sync Implementation
        private func syncFromStrava(
            stravaService: StravaService,
            userFTP: Double,
            userLTHR: Double?,
            startDate: Date?
        ) async {
            syncStatus = "Syncing from Strava..."
            syncProgress = 0.1
            
            do {
                let syncStart = startDate ?? lastSyncDate ?? Calendar.current.date(byAdding: .day, value: -90, to: Date())!
                
                let stravaActivities = try await stravaService.fetchAllActivitiesForTrainingLoad(startDate: syncStart)
                
                guard !stravaActivities.isEmpty else {
                    syncStatus = "No new Strava activities"
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    return
                }
                
                syncProgress = 0.5
                syncStatus = "Processing \(stravaActivities.count) activities..."
                
                let universalActivities = stravaActivities.map { activity -> UniversalActivity in
                    UniversalActivity(
                        id: "\(activity.id)",
                        name: activity.name,
                        type: mapStravaType(activity.type),
                        startDate: activity.startDate,
                        duration: TimeInterval(activity.movingTime),
                        distance: activity.distance,
                        averagePower: activity.averageWatts,
                        averageHeartRate: activity.averageHeartrate,
                        maxHeartRate: activity.maxHeartrate,
                        calories: activity.kilojoules,
                        source: .strava
                    )
                }
                
                await processActivities(universalActivities, userFTP: userFTP, userLTHR: userLTHR)
                syncStatus = "✅ Synced \(stravaActivities.count) from Strava"
                
            } catch {
                syncStatus = "Strava sync failed: \(error.localizedDescription)"
            }
        }
    
    // MARK: - 2. Garmin Sync Implementation (With Chunking Fix)
        private func syncFromGarmin(
            garminService: GarminService,
            userFTP: Double,
            userLTHR: Double?,
            startDate: Date?
        ) async {
            syncStatus = "Syncing from Garmin..."
            syncProgress = 0.1
            
            do {
                // Default to 30 days if no date provided
                let syncStart = startDate ?? Calendar.current.date(byAdding: .day, value: -30, to: Date())!
                let today = Date()
                let calendar = Calendar.current
                
                var allActivities: [GarminActivity] = []
                
                // Chunking Loop: Break request into daily chunks to avoid 400 Error
                var currentStart = syncStart
                while currentStart < today {
                    let currentEnd = min(calendar.date(byAdding: .day, value: 1, to: currentStart)!, today)
                    
                    syncStatus = "Fetching Garmin data (\(currentStart.formatted(date: .abbreviated, time: .omitted)))..."
                    
                    // Call the API with explicit start/end
                    if let activities = try? await garminService.fetchActivities(startDate: currentStart, endDate: currentEnd) {
                        allActivities.append(contentsOf: activities)
                    }
                    
                    currentStart = currentEnd
                    // Tiny pause to be nice to the API
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                }
                
                guard !allActivities.isEmpty else {
                    syncStatus = "No new Garmin activities"
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    return
                }
                
                syncProgress = 0.5
                syncStatus = "Processing \(allActivities.count) activities..."
                
                let universalActivities = allActivities.map { activity -> UniversalActivity in
                    UniversalActivity(
                        id: "\(activity.activityId)",
                        name: activity.activityName,
                        type: mapGarminType(activity.activityType),
                        startDate: activity.startTime,
                        duration: TimeInterval(activity.duration),
                        distance: activity.distance,
                        averagePower: activity.avgPower,
                        averageHeartRate: activity.avgHeartRate,
                        maxHeartRate: activity.maxHeartRate,
                        calories: activity.calories,
                        source: .garmin
                    )
                }
                
                await processActivities(universalActivities, userFTP: userFTP, userLTHR: userLTHR)
                syncStatus = "✅ Synced \(allActivities.count) from Garmin"
                
            } catch {
                syncStatus = "Garmin sync failed: \(error.localizedDescription)"
                print("Garmin Error: \(error)")
            }
        }
    
    // MARK: - 3. Apple Health Sync Implementation
        private func syncFromAppleHealth(
            healthManager: HealthKitManager,
            userFTP: Double,
            userLTHR: Double?,
            startDate: Date?
        ) async {
            syncStatus = "Analyzing HealthKit..."
            syncProgress = 0.1
            
            let syncStart = startDate ?? lastSyncDate ?? Calendar.current.date(byAdding: .day, value: -90, to: Date())!
            let syncEnd = Date()
            
            let workouts = await healthManager.fetchWorkouts(startDate: syncStart, endDate: syncEnd)
            
            guard !workouts.isEmpty else {
                syncStatus = "No new HealthKit workouts"
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                return
            }
            
            syncProgress = 0.3
            var universalActivities: [UniversalActivity] = []
            
            for (index, workout) in workouts.enumerated() {
                let avgHR = await healthManager.fetchAverageHeartRate(for: workout)
                let maxHR = await healthManager.fetchMaxHeartRate(for: workout)
                
                let activity = UniversalActivity(
                    id: workout.uuid.uuidString,
                    name: workout.workoutActivityType.name,
                    type: mapHealthKitType(workout.workoutActivityType),
                    startDate: workout.startDate,
                    duration: workout.duration,
                    distance: workout.totalDistance?.doubleValue(for: .meter()) ?? 0,
                    averagePower: nil,
                    averageHeartRate: avgHR,
                    maxHeartRate: maxHR,
                    calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                    source: .appleHealth
                )
                universalActivities.append(activity)
                
                // Update UI occasionally
                if index % 5 == 0 {
                    syncStatus = "Processing \(index)/\(workouts.count)..."
                    syncProgress = 0.3 + (0.6 * Double(index) / Double(workouts.count))
                }
            }
            
            await processActivities(universalActivities, userFTP: userFTP, userLTHR: userLTHR)
            syncStatus = "✅ Synced \(workouts.count) from Health"
        }
        
        // MARK: - Common Processing Logic
        private func processActivities(
            _ activities: [UniversalActivity],
            userFTP: Double,
            userLTHR: Double?
        ) async {
            syncStatus = "Updating metrics..."
            var dailyData: [Date: (tss: Double, count: Int, distance: Double, duration: TimeInterval)] = [:]
            
            for activity in activities {
                let calendar = Calendar.current
                let activityDate = calendar.startOfDay(for: activity.startDate)
                let tss = activity.calculateTSS(userFTP: userFTP, userLTHR: userLTHR)
                
                if var existing = dailyData[activityDate] {
                    existing.tss += tss
                    existing.count += 1
                    existing.distance += activity.distance
                    existing.duration += activity.duration
                    dailyData[activityDate] = existing
                } else {
                    dailyData[activityDate] = (tss, 1, activity.distance, activity.duration)
                }
            }
            
            for (date, data) in dailyData {
                trainingLoadManager.updateDailyLoad(
                    date: date,
                    tss: data.tss,
                    rideCount: data.count,
                    distance: data.distance,
                    duration: data.duration
                )
            }
            
            trainingLoadManager.fillMissingDays()
            syncProgress = 1.0
        }
    
    // MARK: - Mappers
        private func mapStravaType(_ type: String) -> UniversalActivity.ActivityType {
            switch type {
            case "Ride": return .ride
            case "VirtualRide": return .virtualRide
            case "Run", "VirtualRun": return .run
            case "Swim": return .swim
            default: return .other
            }
        }
        
        private func mapGarminType(_ type: String) -> UniversalActivity.ActivityType {
            let lower = type.lowercased()
            if lower.contains("cycling") || lower.contains("bike") { return .ride }
            if lower.contains("run") { return .run }
            if lower.contains("swim") { return .swim }
            return .other
        }
        
        private func mapHealthKitType(_ type: HKWorkoutActivityType) -> UniversalActivity.ActivityType {
            switch type {
            case .cycling: return .ride
            case .running: return .run
            case .swimming: return .swim
            default: return .other
            }
        }
        
        enum SyncError: LocalizedError {
            case notConnected(String)
            var errorDescription: String? {
                switch self {
                case .notConnected(let source): return "Please connect to \(source) in Settings > Data Sources."
                }
            }
        }
    }
    


// MARK: - Backwards Compatibility
typealias TrainingLoadSyncManager = UnifiedTrainingLoadSync

// MARK: - HealthKit Extensions

extension HealthKitManager {
    
    /// Fetches workouts from HealthKit within a date range
    func fetchWorkouts(startDate: Date, endDate: Date) async -> [HKWorkout] {
        guard isAuthorized else { return [] }
        
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    print("HealthKit: Error fetching workouts: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }
                
                let workouts = samples as? [HKWorkout] ?? []
                print("HealthKit: Fetched \(workouts.count) workouts")
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
    }
    
    /// Fetches average heart rate for a specific workout
    func fetchAverageHeartRate(for workout: HKWorkout) async -> Double? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: hrType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error = error {
                    print("HealthKit: Error fetching HR: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                let avgHR = statistics?.averageQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
                continuation.resume(returning: avgHR)
            }
            healthStore.execute(query)
        }
    }
    
    /// Fetches max heart rate for a specific workout
    func fetchMaxHeartRate(for workout: HKWorkout) async -> Double? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: hrType,
                quantitySamplePredicate: predicate,
                options: .discreteMax
            ) { _, statistics, error in
                if let error = error {
                    print("HealthKit: Error fetching max HR: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                let maxHR = statistics?.maximumQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
                continuation.resume(returning: maxHR)
            }
            healthStore.execute(query)
        }
    }
}

// MARK: - HKWorkoutActivityType Extension

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .cycling: return "Cycling"
        case .running: return "Running"
        case .swimming: return "Swimming"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        default: return "Workout"
        }
    }
}
