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
        
        // Priority: Garmin > Strava > Apple Health
        if garminService.isAuthenticated {
            await syncFromGarmin(
                garminService: garminService,
                userFTP: userFTP,
                userLTHR: userLTHR,
                startDate: startDate
            )
        } else if stravaService.isAuthenticated {
            await syncFromStrava(
                stravaService: stravaService,
                userFTP: userFTP,
                userLTHR: userLTHR,
                startDate: startDate
            )
        } else if healthManager.isAuthorized {
            await syncFromAppleHealth(
                healthManager: healthManager,
                userFTP: userFTP,
                userLTHR: userLTHR,
                startDate: startDate
            )
        } else {
            syncStatus = "No data source connected"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            syncStatus = ""
        }
    }
    
    // MARK: - Strava Sync
    
    private func syncFromStrava(
        stravaService: StravaService,
        userFTP: Double,
        userLTHR: Double?,
        startDate: Date?
    ) async {
        isSyncing = true
        syncProgress = 0
        syncStatus = "Syncing from Strava..."
        
        do {
            let syncStart = startDate ?? lastSyncDate ?? Calendar.current.date(byAdding: .day, value: -365, to: Date())!
            
            syncProgress = 0.2
            let stravaActivities = try await stravaService.fetchAllActivitiesForTrainingLoad(startDate: syncStart)
            
            guard !stravaActivities.isEmpty else {
                syncStatus = "No new Strava activities"
                lastSyncDate = Date()
                saveSyncDate()
                isSyncing = false
                needsSync = false
                return
            }
            
            syncProgress = 0.4
            syncStatus = "Processing \(stravaActivities.count) activities..."
            
            // Convert to universal format
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
            
            lastSyncDate = Date()
            saveSyncDate()
            needsSync = false
            syncStatus = "✅ Synced \(stravaActivities.count) from Strava"
            syncProgress = 1.0
            
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            syncStatus = ""
            
        } catch {
            syncStatus = "Strava sync failed: \(error.localizedDescription)"
            print("❌ Strava sync error: \(error)")
        }
        
        isSyncing = false
    }
    
    // MARK: - Garmin Sync
    
    private func syncFromGarmin(
        garminService: GarminService,
        userFTP: Double,
        userLTHR: Double?,
        startDate: Date?
    ) async {
        isSyncing = true
        syncProgress = 0
        syncStatus = "Syncing from Garmin..."
        
        do {
            let syncStart = startDate ?? lastSyncDate ?? Calendar.current.date(byAdding: .day, value: -365, to: Date())!
            
            syncProgress = 0.2
            
            // Fetch activities from Garmin
            let garminActivities = try await garminService.fetchActivitiesForTraining(startDate: syncStart)
            
            guard !garminActivities.isEmpty else {
                syncStatus = "No new Garmin activities"
                lastSyncDate = Date()
                saveSyncDate()
                isSyncing = false
                needsSync = false
                return
            }
            
            syncProgress = 0.4
            syncStatus = "Processing \(garminActivities.count) activities..."
            
            // Convert to universal format
            let universalActivities = garminActivities.map { activity -> UniversalActivity in
                UniversalActivity(
                    id: "\(activity.activityId)",
                    name: activity.activityName ?? "Garmin Activity",
                    type: mapGarminType(activity.activityType),
                    startDate: activity.startDate,
                    duration: TimeInterval(activity.durationInSeconds),
                    distance: activity.distanceInMeters ?? 0,
                    averagePower: activity.averagePowerInWatts,
                    averageHeartRate: activity.averageHeartRateInBeatsPerMinute.map { Double($0) },
                    maxHeartRate: activity.maxHeartRateInBeatsPerMinute.map { Double($0) },
                    calories: activity.activeKilocalories,
                    source: .garmin
                )
            }
            
            await processActivities(universalActivities, userFTP: userFTP, userLTHR: userLTHR)
            
            lastSyncDate = Date()
            saveSyncDate()
            needsSync = false
            syncStatus = "✅ Synced \(garminActivities.count) from Garmin"
            syncProgress = 1.0
            
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            syncStatus = ""
            
        } catch {
            syncStatus = "Garmin sync failed: \(error.localizedDescription)"
            print("❌ Garmin sync error: \(error)")
        }
        
        isSyncing = false
    }
    
    // MARK: - Apple Health Sync
    
    private func syncFromAppleHealth(
        healthManager: HealthKitManager,
        userFTP: Double,
        userLTHR: Double?,
        startDate: Date?
    ) async {
        isSyncing = true
        syncProgress = 0
        syncStatus = "Syncing from Apple Health..."
        
        do {
            let syncStart = startDate ?? lastSyncDate ?? Calendar.current.date(byAdding: .day, value: -90, to: Date())!
            let syncEnd = Date()
            
            syncProgress = 0.2
            
            // Fetch workouts from HealthKit
            let workouts = await healthManager.fetchWorkouts(startDate: syncStart, endDate: syncEnd)
            
            guard !workouts.isEmpty else {
                syncStatus = "No new Apple Health workouts"
                lastSyncDate = Date()
                saveSyncDate()
                isSyncing = false
                needsSync = false
                return
            }
            
            syncProgress = 0.4
            syncStatus = "Processing \(workouts.count) workouts..."
            
            // Convert to universal format
            var universalActivities: [UniversalActivity] = []
            
            for (index, workout) in workouts.enumerated() {
                // Fetch heart rate samples for this workout
                let avgHR = await healthManager.fetchAverageHeartRate(for: workout)
                let maxHR = await healthManager.fetchMaxHeartRate(for: workout)
                
                let activity = UniversalActivity(
                    id: workout.uuid.uuidString,
                    name: workout.workoutActivityType.name,
                    type: mapHealthKitType(workout.workoutActivityType),
                    startDate: workout.startDate,
                    duration: workout.duration,
                    distance: workout.totalDistance?.doubleValue(for: .meter()) ?? 0,
                    averagePower: nil, // HealthKit doesn't typically have power
                    averageHeartRate: avgHR,
                    maxHeartRate: maxHR,
                    calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                    source: .appleHealth
                )
                
                universalActivities.append(activity)
                syncProgress = 0.4 + (0.4 * Double(index) / Double(workouts.count))
            }
            
            await processActivities(universalActivities, userFTP: userFTP, userLTHR: userLTHR)
            
            lastSyncDate = Date()
            saveSyncDate()
            needsSync = false
            syncStatus = "✅ Synced \(workouts.count) from Apple Health"
            syncProgress = 1.0
            
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            syncStatus = ""
            
        } catch {
            syncStatus = "Apple Health sync failed: \(error.localizedDescription)"
            print("❌ Apple Health sync error: \(error)")
        }
        
        isSyncing = false
    }
    
    // MARK: - Common Processing
    
    private func processActivities(
        _ activities: [UniversalActivity],
        userFTP: Double,
        userLTHR: Double?
    ) async {
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
                dailyData[activityDate] = (
                    tss: tss,
                    count: 1,
                    distance: activity.distance,
                    duration: activity.duration
                )
            }
        }
        
        syncStatus = "Updating training load..."
        syncProgress = 0.9
        
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
    }
    
    // MARK: - Type Mapping
    
    private func mapStravaType(_ type: String) -> UniversalActivity.ActivityType {
        switch type {
        case "Ride": return .ride
        case "VirtualRide": return .virtualRide
        case "Run", "VirtualRun": return .run
        case "Swim": return .swim
        default: return .other
        }
    }
    
    private func mapHealthKitType(_ type: HKWorkoutActivityType) -> UniversalActivity.ActivityType {
        switch type {
        case .cycling: return .ride
        case .running: return .run
        case .swimming: return .swim
        default: return .other
        }
    }
    
    private func mapGarminType(_ type: String) -> UniversalActivity.ActivityType {
        let lowerType = type.lowercased()
        if lowerType.contains("cycling") || lowerType.contains("bike") || lowerType.contains("biking") {
            return .ride
        } else if lowerType.contains("running") || lowerType.contains("run") {
            return .run
        } else if lowerType.contains("swimming") || lowerType.contains("swim") {
            return .swim
        } else {
            return .other
        }
    }
    
    // MARK: - Persistence
    
    private func saveSyncDate() {
        if let date = lastSyncDate {
            UserDefaults.standard.set(date, forKey: "unifiedTrainingLoadSync")
        }
    }
    
    func loadSyncDate() {
        lastSyncDate = UserDefaults.standard.object(forKey: "unifiedTrainingLoadSync") as? Date
        if let lastSync = lastSyncDate {
            needsSync = Date().timeIntervalSince(lastSync) > 3600 // 1 hour
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
