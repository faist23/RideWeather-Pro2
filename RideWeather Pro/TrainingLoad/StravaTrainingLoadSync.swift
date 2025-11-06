//
//  StravaTrainingLoadSync.swift
//  RideWeather Pro
//
//  Automatic sync of all Strava activities for training load calculation
//

import Foundation
import Combine


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

// MARK: - Training Load Sync Manager

@MainActor
class TrainingLoadSyncManager: ObservableObject {
    @Published var isSyncing = false
    @Published var syncProgress: Double = 0
    @Published var lastSyncDate: Date?
    @Published var syncStatus: String = ""
    @Published var syncError: String?
    
    private let trainingLoadManager = TrainingLoadManager.shared
    
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
                print("🔍 DEBUG: Using default 90 days ago")
            }
            
            print("🔍 DEBUG: Final syncStart = \(syncStart.formatted(date: .abbreviated, time: .shortened))")
            
            syncStatus = "Fetching activities..."
            syncProgress = 0.2
            
            let activities = try await stravaService.fetchAllActivitiesForTrainingLoad(startDate: syncStart)
            
            guard !activities.isEmpty else {
                syncStatus = "No new activities found"
                syncProgress = 1.0
                
                // --- THIS IS THE FIX ---
                // Update the sync date *before* returning
                lastSyncDate = Date()
                saveSyncDate()
                print("✅ Training Load Sync Complete: 0 new activities found.")
                
                // Delay to show the "No new activities" message
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if syncStatus == "No new activities found" {
                    syncStatus = ""
                }
                
                isSyncing = false // Make sure to set this
                return              // Restore the required return
                // --- END FIX ---
            }
            
            syncStatus = "Processing \(activities.count) activities..."
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
            
            syncStatus = "✅ Synced \(activities.count) activities"
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
        
        // ADD THIS: Recalculate metrics after updating
        let updatedLoads = recalculateMetrics(for: dailyLoads)
        saveDailyLoads(updatedLoads)
    }
}
