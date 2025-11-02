//
//  StravaActivitySummary.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 11/1/25.
//


//
//  StravaTrainingLoadSync.swift
//  RideWeather Pro
//
//  Automatic sync of all Strava activities for training load calculation
//

import Foundation

// MARK: - Add to StravaService.swift

extension StravaService {
    
    /// Fetches ALL activities (not just rides) for training load calculation
    /// This includes runs, swims, etc. - anything with moving_time and suffer_score
    func fetchAllActivitiesForTrainingLoad(
        startDate: Date,
        endDate: Date = Date()
    ) async throws -> [StravaActivitySummary] {
        
        await refreshTokenIfNeededAsync()
        
        guard let accessToken = currentTokens?.accessToken else {
            throw StravaError.notAuthenticated
        }
        
        // Convert dates to Unix timestamps
        let startTimestamp = Int(startDate.timeIntervalSince1970)
        let endTimestamp = Int(endDate.timeIntervalSince1970)
        
        var allActivities: [StravaActivitySummary] = []
        var currentPage = 1
        let perPage = 200 // Max allowed by Strava
        
        while true {
            var components = URLComponents(string: "https://www.strava.com/api/v3/athlete/activities")!
            components.queryItems = [
                URLQueryItem(name: "after", value: String(startTimestamp)),
                URLQueryItem(name: "before", value: String(endTimestamp)),
                URLQueryItem(name: "per_page", value: String(perPage)),
                URLQueryItem(name: "page", value: String(currentPage))
            ]
            
            guard let url = components.url else {
                throw StravaError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw StravaError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw StravaError.apiError(statusCode: httpResponse.statusCode)
            }
            
            let activities = try JSONDecoder().decode([StravaActivity].self, from: data)
            
            if activities.isEmpty {
                break // No more activities
            }
            
            // Convert to summary format
            let summaries = activities.map { activity in
                StravaActivitySummary(
                    id: activity.id,
                    name: activity.name,
                    type: activity.type,
                    startDate: activity.startDate ?? Date(),
                    movingTime: activity.moving_time,
                    elapsedTime: activity.elapsed_time,
                    distance: activity.distance,
                    averageWatts: activity.average_watts,
                    weightedAverageWatts: activity.average_watts, // Strava doesn't expose NP directly
                    sufferScore: activity.suffer_score,
                    averageHeartrate: activity.average_heartrate,
                    maxHeartrate: activity.max_heartrate,
                    kilojoules: activity.kilojoules
                )
            }
            
            allActivities.append(contentsOf: summaries)
            
            if activities.count < perPage {
                break // Last page
            }
            
            currentPage += 1
        }
        
        print("📊 Strava Sync: Fetched \(allActivities.count) activities from \(startDate.formatted(date: .abbreviated, time: .omitted)) to \(endDate.formatted(date: .abbreviated, time: .omitted))")
        
        return allActivities
    }
}

// MARK: - Simplified Activity Summary Model

struct StravaActivitySummary: Codable {
    let id: Int
    let name: String
    let type: String // "Ride", "Run", "Swim", "VirtualRide", etc.
    let startDate: Date
    let movingTime: Int // seconds
    let elapsedTime: Int
    let distance: Double // meters
    let averageWatts: Double?
    let weightedAverageWatts: Double?
    let sufferScore: Double? // Strava's TSS equivalent
    let averageHeartrate: Double?
    let maxHeartrate: Double?
    let kilojoules: Double?
    
    /// Estimates TSS from available data
    func estimateTSS(userFTP: Double, userLTHR: Double? = nil) -> Double {
        // Priority 1: Use Strava's Suffer Score if available (it's basically TSS)
        if let sufferScore = sufferScore {
            return sufferScore
        }
        
        // Priority 2: Calculate from power data
        if let avgWatts = averageWatts, avgWatts > 0, userFTP > 0 {
            let hours = Double(movingTime) / 3600.0
            let intensityFactor = avgWatts / userFTP
            return hours * intensityFactor * intensityFactor * 100
        }
        
        // Priority 3: Calculate from heart rate
        if let avgHR = averageHeartrate, let lthr = userLTHR, lthr > 0 {
            let hours = Double(movingTime) / 3600.0
            let intensityFactor = avgHR / lthr
            return hours * intensityFactor * intensityFactor * 100
        }
        
        // Priority 4: Estimate from kilojoules (rough approximation)
        if let kj = kilojoules, kj > 0 {
            // TSS ≈ kJ / (FTP * 3.6)
            return kj / (userFTP * 3.6)
        }
        
        // Fallback: Estimate from duration and activity type
        return estimateTSSFromDuration()
    }
    
    private func estimateTSSFromDuration() -> Double {
        let hours = Double(movingTime) / 3600.0
        
        // Rough estimates based on activity type
        let estimatedIF: Double
        switch type {
        case "Race", "WorkOut":
            estimatedIF = 0.95 // Hard effort
        case "Ride", "VirtualRide":
            estimatedIF = 0.70 // Moderate ride
        case "Run":
            estimatedIF = 0.75 // Running is typically harder
        case "Swim":
            estimatedIF = 0.65 // Swimming
        default:
            estimatedIF = 0.65 // Conservative estimate
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
    
    /// Syncs all activities from Strava since last sync (or specified date)
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
            // Determine start date (last sync or 90 days ago)
            let syncStart = startDate ?? lastSyncDate ?? Calendar.current.date(byAdding: .day, value: -90, to: Date())!
            
            syncStatus = "Fetching activities..."
            syncProgress = 0.2
            
            // Fetch all activities
            let activities = try await stravaService.fetchAllActivitiesForTrainingLoad(
                startDate: syncStart
            )
            
            guard !activities.isEmpty else {
                syncStatus = "No new activities found"
                isSyncing = false
                return
            }
            
            syncStatus = "Processing \(activities.count) activities..."
            syncProgress = 0.4
            
            // Group activities by day and calculate TSS
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
                
                // Update progress
                syncProgress = 0.4 + (0.5 * Double(index) / Double(activities.count))
            }
            
            syncStatus = "Updating training load..."
            syncProgress = 0.9
            
            // Update training load for each day
            for (date, data) in dailyData {
                trainingLoadManager.updateDailyLoad(
                    date: date,
                    tss: data.tss,
                    rideCount: data.count,
                    distance: data.distance,
                    duration: data.duration
                )
            }
            
            // Fill missing days and recalculate
            trainingLoadManager.fillMissingDays()
            
            lastSyncDate = Date()
            saveSyncDate()
            
            syncStatus = "✅ Synced \(activities.count) activities"
            syncProgress = 1.0
            
            print("✅ Training Load Sync Complete: \(activities.count) activities processed")
            
            // Clear status after 2 seconds
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
    
    /// Quick check if sync is needed (more than 24 hours since last sync)
    var needsSync: Bool {
        guard let lastSync = lastSyncDate else { return true }
        return Date().timeIntervalSince(lastSync) > 86400 // 24 hours
    }
}

// MARK: - Add to TrainingLoadManager.swift

extension TrainingLoadManager {
    
    /// Updates or creates a daily load entry (used by sync)
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
            // Update existing
            dailyLoads[existingIndex].tss = tss
            dailyLoads[existingIndex].rideCount = rideCount
            dailyLoads[existingIndex].totalDistance = distance
            dailyLoads[existingIndex].totalDuration = duration
        } else {
            // Create new
            dailyLoads.append(DailyTrainingLoad(
                date: dayStart,
                tss: tss,
                rideCount: rideCount,
                totalDistance: distance,
                totalDuration: duration
            ))
        }
        
        dailyLoads.sort { $0.date < $1.date }
        saveDailyLoads(dailyLoads)
    }
}