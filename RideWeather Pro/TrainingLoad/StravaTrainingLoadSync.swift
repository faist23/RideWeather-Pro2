//
//  UnifiedTrainingLoadSync.swift
//  RideWeather Pro
//
//  Automatic sync of all activities for training load calculation
//  Supports: Strava, Garmin, Apple Health
//

import Foundation
import Combine

// MARK: - Data Source Enum

enum DataSource: String, Codable {
    case strava = "Strava"
    case garmin = "Garmin"
    case appleHealth = "Apple Health"
    case wahoo = "Wahoo"
    case manual = "Manual Entry"
}

// MARK: - Activity Summary Model

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
    
    func estimateTSS(userFTP: Double, userLTHR: Double? = nil) -> Double {
        if let sufferScore = sufferScore {
            return sufferScore
        }
        
        if let avgWatts = averageWatts, avgWatts > 0, userFTP > 0 {
            let hours = Double(movingTime) / 3600.0
            let intensityFactor = avgWatts / userFTP
            return hours * intensityFactor * intensityFactor * 100
        }
        
        if let avgHR = averageHeartrate, let lthr = userLTHR, lthr > 0 {
            let hours = Double(movingTime) / 3600.0
            let intensityFactor = avgHR / lthr
            return hours * intensityFactor * intensityFactor * 100
        }
        
        if let kj = kilojoules, kj > 0 {
            return kj / (userFTP * 3.6)
        }
        
        return estimateTSSFromDuration()
    }
    
    private func estimateTSSFromDuration() -> Double {
        let hours = Double(movingTime) / 3600.0
        let estimatedIF: Double
        
        switch type {
        case "Race", "WorkOut": estimatedIF = 0.95
        case "Ride", "VirtualRide": estimatedIF = 0.70
        case "Run": estimatedIF = 0.75
        case "Swim": estimatedIF = 0.65
        default: estimatedIF = 0.65
        }
        
        return hours * estimatedIF * estimatedIF * 100
    }
    
    var activityEmoji: String {
        switch type {
        case "Ride", "VirtualRide": return "🚴"
        case "Run", "VirtualRun": return "🏃"
        case "Swim": return "🏊"
        case "Walk", "Hike": return "🥾"
        case "WeightTraining": return "🏋️"
        case "Yoga": return "🧘"
        default: return "💪"
        }
    }
}

// MARK: - Unified Training Load Sync Manager

@MainActor
class UnifiedTrainingLoadSync: ObservableObject {
    @Published var isSyncing = false
    @Published var syncProgress: Double = 0
    @Published var lastSyncDate: Date?
    @Published var syncStatus: String = ""
    @Published var syncError: String?
    
    private let trainingLoadManager = TrainingLoadManager.shared
    
    // MARK: - Unified Sync Method
    
    /// Syncs from whichever source is available and configured
    func syncFromConfiguredSource(
        stravaService: StravaService,
        garminService: GarminService,
        healthManager: HealthKitManager,
        userFTP: Double,
        userLTHR: Double? = nil,
        startDate: Date? = nil
    ) async {
        guard !isSyncing else { return }
        
        // Determine which source to use (priority: Garmin > Strava > Apple Health)
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
            // Apple Health sync for workouts (future implementation)
            syncStatus = "Apple Health training sync not yet implemented"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            syncStatus = ""
        } else {
            syncStatus = "No data source connected"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            syncStatus = ""
        }
    }
    
    // MARK: - Strava Sync
    
    func syncFromStrava(
        stravaService: StravaService,
        userFTP: Double,
        userLTHR: Double? = nil,
        startDate: Date? = nil
    ) async {
        guard !isSyncing else { return }
        
        isSyncing = true
        syncProgress = 0
        syncError = nil
        syncStatus = "Connecting to Strava..."
        
        do {
            print("🔍 DEBUG: startDate parameter = \(startDate?.formatted(date: .abbreviated, time: .shortened) ?? "nil")")
            print("🔍 DEBUG: lastSyncDate = \(lastSyncDate?.formatted(date: .abbreviated, time: .shortened) ?? "nil")")
            
            let syncStart: Date
            if let explicitStart = startDate {
                syncStart = explicitStart
                print("🔍 DEBUG: Using explicit startDate")
            } else if let lastSync = lastSyncDate {
                syncStart = lastSync
                print("🔍 DEBUG: Using lastSyncDate")
            } else {
                syncStart = Calendar.current.date(byAdding: .day, value: -365, to: Date())!
                print("🔍 DEBUG: Using default 365 days ago")
            }
            
            print("🔍 DEBUG: Final syncStart = \(syncStart.formatted(date: .abbreviated, time: .shortened))")
            
            syncStatus = "Fetching Strava activities..."
            syncProgress = 0.2
            
            let activities = try await stravaService.fetchAllActivitiesForTrainingLoad(startDate: syncStart)
            
            guard !activities.isEmpty else {
                syncStatus = "No new activities found"
                syncProgress = 1.0
                
                lastSyncDate = Date()
                saveSyncDate()
                print("✅ Training Load Sync Complete: 0 new activities found.")
                
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if syncStatus == "No new activities found" {
                    syncStatus = ""
                }
                
                isSyncing = false
                return
            }
            
            syncStatus = "Processing \(activities.count) Strava activities..."
            syncProgress = 0.4
            
            var dailyData: [Date: (tss: Double, count: Int, distance: Double, duration: TimeInterval)] = [:]
            
            for (index, activity) in activities.enumerated() {
                let calendar = Calendar.current
                let activityDate = calendar.startOfDay(for: activity.startDate)
                let tss = activity.estimateTSS(userFTP: userFTP, userLTHR: userLTHR)
                
                if var existing = dailyData[activityDate] {
                    existing.tss += tss
                    existing.count += 1
                    existing.distance += activity.distance
                    existing.duration += TimeInterval(activity.movingTime)
                    dailyData[activityDate] = existing
                } else {
                    dailyData[activityDate] = (
                        tss: tss,
                        count: 1,
                        distance: activity.distance,
                        duration: TimeInterval(activity.movingTime)
                    )
                }
                
                syncProgress = 0.4 + (0.5 * Double(index) / Double(activities.count))
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
            trainingLoadManager.debugPrintLoadData()
            
            lastSyncDate = Date()
            saveSyncDate()
            
            syncStatus = "✅ Synced \(activities.count) Strava activities"
            syncProgress = 1.0
            
            print("✅ Training Load Sync Complete: \(activities.count) activities processed")
            
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if syncStatus.starts(with: "✅") {
                syncStatus = ""
            }
            
        } catch {
            syncError = error.localizedDescription
            syncStatus = "Sync failed"
            print("❌ Training Load Sync Error: \(error)")
        }
        
        isSyncing = false
    }
    
    // MARK: - Garmin Sync
    
    func syncFromGarmin(
        garminService: GarminService,
        userFTP: Double,
        userLTHR: Double? = nil,
        startDate: Date? = nil
    ) async {
        guard !isSyncing else { return }
        
        isSyncing = true
        syncProgress = 0
        syncError = nil
        syncStatus = "Connecting to Garmin..."
        
        do {
            let syncStart: Date
            if let explicitStart = startDate {
                syncStart = explicitStart
            } else if let lastSync = lastSyncDate {
                syncStart = lastSync
            } else {
                syncStart = Calendar.current.date(byAdding: .day, value: -365, to: Date())!
            }
            
            print("🔍 Garmin Sync: Starting from \(syncStart.formatted(date: .abbreviated, time: .shortened))")
            
            syncStatus = "Fetching Garmin activities..."
            syncProgress = 0.2
            
            let activities = try await garminService.fetchActivitiesForTraining(startDate: syncStart)
            
            guard !activities.isEmpty else {
                syncStatus = "No new activities found"
                syncProgress = 1.0
                
                lastSyncDate = Date()
                saveSyncDate()
                print("✅ Garmin Sync Complete: 0 new activities found.")
                
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if syncStatus == "No new activities found" {
                    syncStatus = ""
                }
                
                isSyncing = false
                return
            }
            
            syncStatus = "Processing \(activities.count) Garmin activities..."
            syncProgress = 0.4
            
            var dailyData: [Date: (tss: Double, count: Int, distance: Double, duration: TimeInterval)] = [:]
            
            for (index, activity) in activities.enumerated() {
                let calendar = Calendar.current
                let activityDate = calendar.startOfDay(for: activity.startDate)
                let tss = calculateTSS(activity: activity, userFTP: userFTP, userLTHR: userLTHR)
                
                if var existing = dailyData[activityDate] {
                    existing.tss += tss
                    existing.count += 1
                    existing.distance += (activity.distanceInMeters ?? 0)
                    existing.duration += TimeInterval(activity.durationInSeconds)
                    dailyData[activityDate] = existing
                } else {
                    dailyData[activityDate] = (
                        tss: tss,
                        count: 1,
                        distance: activity.distanceInMeters ?? 0,
                        duration: TimeInterval(activity.durationInSeconds)
                    )
                }
                
                syncProgress = 0.4 + (0.5 * Double(index) / Double(activities.count))
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
            trainingLoadManager.debugPrintLoadData()
            
            lastSyncDate = Date()
            saveSyncDate()
            
            syncStatus = "✅ Synced \(activities.count) Garmin activities"
            syncProgress = 1.0
            
            print("✅ Garmin Sync Complete: \(activities.count) activities processed")
            
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if syncStatus.starts(with: "✅") {
                syncStatus = ""
            }
            
        } catch {
            syncError = error.localizedDescription
            syncStatus = "Garmin sync failed"
            print("❌ Garmin Sync Error: \(error)")
        }
        
        isSyncing = false
    }
    
    // MARK: - Garmin TSS Calculation
    
    private func calculateTSS(
        activity: GarminTrainingActivity,
        userFTP: Double,
        userLTHR: Double?
    ) -> Double {
        let durationHours = Double(activity.durationInSeconds) / 3600.0
        
        // Priority 1: Normalized Power
        if let np = activity.normalizedPowerInWatts, userFTP > 0 {
            let intensityFactor = np / userFTP
            let tss = (Double(activity.durationInSeconds) * np * intensityFactor) / (userFTP * 3600) * 100
            return tss
        }
        
        // Priority 2: Average Power
        if let avgPower = activity.averagePowerInWatts, userFTP > 0 {
            let intensityFactor = avgPower / userFTP
            let tss = (Double(activity.durationInSeconds) * avgPower * intensityFactor) / (userFTP * 3600) * 100
            return tss
        }
        
        // Priority 3: Heart Rate
        if let avgHR = activity.averageHeartRateInBeatsPerMinute,
           let lthr = userLTHR, lthr > 0 {
            let hrRatio = Double(avgHR) / lthr
            let tss = durationHours * hrRatio * hrRatio * 100
            return tss
        }
        
        // Priority 4: Distance-based estimate
        if let distance = activity.distanceInMeters {
            let distanceKm = distance / 1000.0
            
            if activity.activityType.lowercased().contains("cycling") ||
               activity.activityType.lowercased().contains("bike") {
                return distanceKm * 1.0 // ~1 TSS per km for moderate cycling
            } else if activity.activityType.lowercased().contains("running") ||
                      activity.activityType.lowercased().contains("run") {
                return distanceKm * 2.5 // Running is more intense
            }
        }
        
        // Priority 5: Duration-based fallback
        return durationHours * 40 // 40 TSS per hour for moderate activity
    }
    
    // MARK: - Helper Methods
    
    private func saveSyncDate() {
        if let date = lastSyncDate {
            UserDefaults.standard.set(date, forKey: "lastTrainingLoadSync")
        }
    }
    
    func loadSyncDate() {
        lastSyncDate = UserDefaults.standard.object(forKey: "lastTrainingLoadSync") as? Date
    }
    
    var needsSync: Bool {
        guard let lastSync = lastSyncDate else { return true }
        return Date().timeIntervalSince(lastSync) > 3600
    }
}

// MARK: - TrainingLoadManager Extension

extension TrainingLoadManager {
    func updateDailyLoad(
        date: Date,
        tss: Double,
        rideCount: Int,
        distance: Double,
        duration: TimeInterval
    ) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        
        var dailyLoads = loadAllDailyLoads()
        
        if let existingIndex = dailyLoads.firstIndex(where: {
            calendar.isDate($0.date, inSameDayAs: dayStart)
        }) {
            dailyLoads[existingIndex].tss = tss
            dailyLoads[existingIndex].rideCount = rideCount
            dailyLoads[existingIndex].totalDistance = distance
            dailyLoads[existingIndex].totalDuration = duration
        } else {
            dailyLoads.append(DailyTrainingLoad(
                date: dayStart,
                tss: tss,
                rideCount: rideCount,
                totalDistance: distance,
                totalDuration: duration
            ))
        }
        
        dailyLoads.sort { $0.date < $1.date }
        
        // Recalculate metrics after updating
        let updatedLoads = recalculateMetrics(for: dailyLoads)
        saveDailyLoads(updatedLoads)
    }
}

// MARK: - Legacy Type Alias for Backwards Compatibility
typealias TrainingLoadSyncManager = UnifiedTrainingLoadSync
