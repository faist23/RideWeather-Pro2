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
    
    func calculateTSS(userFTP: Double, userLTHR: Double?) -> Double {
        if let avgPower = averagePower, avgPower > 0, userFTP > 0 {
            let hours = duration / 3600.0
            let intensityFactor = avgPower / userFTP
            return hours * intensityFactor * intensityFactor * 100
        }
        
        if let avgHR = averageHeartRate, let lthr = userLTHR, lthr > 0 {
            let hours = duration / 3600.0
            let intensityFactor = avgHR / lthr
            return hours * intensityFactor * intensityFactor * 100
        }
        
        return estimateTSSFromDuration()
    }
    
    private func estimateTSSFromDuration() -> Double {
        let hours = duration / 3600.0
        let estimatedIF: Double
        switch type {
        case .ride, .virtualRide: estimatedIF = 0.70
        case .run: estimatedIF = 0.75
        case .swim: estimatedIF = 0.65
        case .other: estimatedIF = 0.60
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
        if let last = lastSyncDate {
            needsSync = Date().timeIntervalSince(last) > 3600
        } else {
            needsSync = true
        }
    }
    
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
    private func syncFromStrava(stravaService: StravaService, userFTP: Double, userLTHR: Double?, startDate: Date?) async {
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
    
    // MARK: - 2. Garmin Sync Implementation
    private func syncFromGarmin(garminService: GarminService, userFTP: Double, userLTHR: Double?, startDate: Date?) async {
        syncStatus = "Syncing from Garmin (Supabase)..." // Update status text
        syncProgress = 0.1
        do {            
            // Fetch recent activities from Supabase (defaults to limit 50, you might want more)
            let activities = try await garminService.fetchRecentActivities(limit: 100, filter: .allTraining)
            
            guard !activities.isEmpty else {
                syncStatus = "No new Garmin activities"
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                return
            }
            
            syncProgress = 0.5
            syncStatus = "Processing \(activities.count) activities..."
            
            // Map GarminActivitySummary (from Supabase) to UniversalActivity
            let universalActivities = activities.map { activity -> UniversalActivity in
                UniversalActivity(
                    id: "\(activity.activityId)",
                    name: activity.activityName ?? "Garmin Activity",
                    type: mapGarminType(activity.activityType),
                    startDate: Date(timeIntervalSince1970: TimeInterval(activity.startTimeInSeconds)),
                    duration: TimeInterval(activity.durationInSeconds),
                    distance: activity.distanceInMeters ?? 0,
                    averagePower: activity.averagePowerInWatts,
                    averageHeartRate: activity.averageHeartRateInBeatsPerMinute.map { Double($0) },
                    maxHeartRate: nil, // Summary might not have max HR, that's okay
                    calories: activity.activeKilocalories,
                    source: .garmin
                )
            }
            await processActivities(universalActivities, userFTP: userFTP, userLTHR: userLTHR)
            syncStatus = "✅ Synced \(activities.count) from Garmin"
        } catch {
            syncStatus = "Garmin sync failed: \(error.localizedDescription)"
            print("Garmin Error: \(error)")
        }
    }
    
    // MARK: - 3. Apple Health Sync Implementation (Optimized BATCH Processing)
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
        
        // BATCHING: Process in chunks of 25 to allow UI updates and prevent thread explosion
        let batchSize = 25
        var universalActivities: [UniversalActivity] = []
        
        for i in stride(from: 0, to: workouts.count, by: batchSize) {
            let end = min(i + batchSize, workouts.count)
            let batch = Array(workouts[i..<end])
            
            // Process Batch in Parallel
            let batchResults = await withTaskGroup(of: UniversalActivity?.self) { group in
                for workout in batch {
                    group.addTask {
                        // 1. FAST POWER CHECK
                        let avgPower = await healthManager.fetchAveragePower(for: workout)
                        
                        // 2. FAST HR CHECK (Strict No-Query for imports)
                        let avgHR = await healthManager.fetchAverageHeartRate(for: workout)
                        let maxHR = await healthManager.fetchMaxHeartRate(for: workout)
                        
                        // 3. Energy
                        let energyBurned: Double?
                        if #available(iOS 16.0, *) {
                            let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
                            energyBurned = workout.statistics(for: activeEnergyType)?
                                .sumQuantity()?
                                .doubleValue(for: .kilocalorie())
                        } else {
                            energyBurned = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                        }
                        
                        // 4. Thread-safe Helpers
                        let activityType = UnifiedTrainingLoadSync.mapHealthKitTypeStatic(workout.workoutActivityType)
                        let activityName = UnifiedTrainingLoadSync.getActivityNameStatic(workout.workoutActivityType)
                        
                        return UniversalActivity(
                            id: workout.uuid.uuidString,
                            name: activityName,
                            type: activityType,
                            startDate: workout.startDate,
                            duration: workout.duration,
                            distance: workout.totalDistance?.doubleValue(for: .meter()) ?? 0,
                            averagePower: avgPower,
                            averageHeartRate: avgHR,
                            maxHeartRate: maxHR,
                            calories: energyBurned,
                            source: .appleHealth
                        )
                    }
                }
                
                var results: [UniversalActivity] = []
                for await result in group {
                    if let act = result { results.append(act) }
                }
                return results
            }
            
            universalActivities.append(contentsOf: batchResults)
            
            // Update UI
            syncProgress = 0.2 + (0.7 * Double(end) / Double(workouts.count))
            syncStatus = "Processed \(end)/\(workouts.count) workouts..."
        }
        
        await processActivities(universalActivities, userFTP: userFTP, userLTHR: userLTHR)
        syncStatus = "✅ Synced \(workouts.count) from Health"
    }
    
    // MARK: - Common Processing Logic
    private func processActivities(_ activities: [UniversalActivity], userFTP: Double, userLTHR: Double?) async {
        syncStatus = "Updating metrics..."
        var dailyData: [Date: (tss: Double, rideCount: Int, distance: Double, duration: TimeInterval)] = [:]
        
        // 1. ✅ NEW: Find the latest precise date from all activities
        let latestActivityDate = activities.map { $0.startDate }.max()
        
        for activity in activities {
            let calendar = Calendar.current
            let activityDate = calendar.startOfDay(for: activity.startDate)
            let tss = activity.calculateTSS(userFTP: userFTP, userLTHR: userLTHR)
            
            if var existing = dailyData[activityDate] {
                existing.tss += tss
                existing.rideCount += 1
                existing.distance += activity.distance
                existing.duration += activity.duration
                dailyData[activityDate] = existing
            } else {
                dailyData[activityDate] = (tss: tss, rideCount: 1, distance: activity.distance, duration: activity.duration)
            }
        }
        
        // 2. ✅ UPDATED: Pass the precise date to the manager
        trainingLoadManager.updateBatchLoads(dailyData, latestPreciseDate: latestActivityDate)
        
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
    
    nonisolated private static func mapHealthKitTypeStatic(_ type: HKWorkoutActivityType) -> UniversalActivity.ActivityType {
        switch type {
        case .cycling: return .ride
        case .running: return .run
        case .swimming: return .swim
        default: return .other
        }
    }
    
    nonisolated private static func getActivityNameStatic(_ type: HKWorkoutActivityType) -> String {
        switch type {
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

// MARK: - HealthKit Extensions (Optimized for Speed)

extension HealthKitManager {
    
    /// Fetches workouts from HealthKit within a date range
    func fetchWorkouts(startDate: Date, endDate: Date) async -> [HKWorkout] {
        guard isAuthorized else { return [] }
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    print("HealthKit: Error fetching workouts: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                } else {
                    continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - FAST Power Fetcher (No Samples Query)
    func fetchAveragePower(for workout: HKWorkout) async -> Double? {
        // 1. Statistics (Best)
        if let powerType = HKQuantityType.quantityType(forIdentifier: .cyclingPower),
           let stats = workout.statistics(for: powerType),
           let avg = stats.averageQuantity() {
            return avg.doubleValue(for: .watt())
        }
        
        // 2. Metadata (Strava often puts it here)
        if let metadata = workout.metadata {
            if let avgPower = metadata["HKAveragePower"] as? HKQuantity {
                return avgPower.doubleValue(for: .watt())
            }
            if let avgWatts = metadata["HKAverageWatts"] as? HKQuantity { // Common Strava key
                return avgWatts.doubleValue(for: .watt())
            }
        }
        
        return nil // Strict "No Query" policy for speed
    }
    
    // MARK: - FAST HR Fetcher (No Samples Query for Imports)
    func fetchAverageHeartRate(for workout: HKWorkout) async -> Double? {
        // 1. Metadata
        if let metadata = workout.metadata,
           let avgHRQuantity = metadata["HKAverageHeartRate"] as? HKQuantity {
            return avgHRQuantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
        }
        
        // 2. Statistics
        if let stats = workout.statistics(for: HKQuantityType.quantityType(forIdentifier: .heartRate)!),
           let avg = stats.averageQuantity() {
            return avg.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
        }

        // 3. Strict Source Check
        // If it's from Apple, we can query samples (it's fast/indexed).
        // If it's Strava/Garmin/Zwift, we assume they wrote metadata. If not, we skip.
        if workout.sourceRevision.source.bundleIdentifier.hasPrefix("com.apple") {
            return await queryHRSamples(for: workout, type: .discreteAverage)
        }
        
        return nil
    }
    
    func fetchMaxHeartRate(for workout: HKWorkout) async -> Double? {
        // 1. Metadata
        if let metadata = workout.metadata,
           let maxHRQuantity = metadata["HKMaximumHeartRate"] as? HKQuantity {
            return maxHRQuantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
        }
        
        // 2. Source Check
        if workout.sourceRevision.source.bundleIdentifier.hasPrefix("com.apple") {
            return await queryHRSamples(for: workout, type: .discreteMax)
        }
        
        return nil
    }
    
    private func queryHRSamples(for workout: HKWorkout, type: HKStatisticsOptions) async -> Double? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: hrType, quantitySamplePredicate: predicate, options: type) { _, statistics, _ in
                let val: Double?
                if type == .discreteAverage {
                    val = statistics?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
                } else {
                    val = statistics?.maximumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
                }
                continuation.resume(returning: val)
            }
            healthStore.execute(query)
        }
    }
}
