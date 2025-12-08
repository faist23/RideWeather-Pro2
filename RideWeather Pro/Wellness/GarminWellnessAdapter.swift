//
//  GarminWellnessAdapter.swift
//  RideWeather Pro
//
//  Fetches wellness data from Garmin Connect
//

import Foundation
import Combine

// MARK: - Garmin Wellness Models

struct GarminDailySummary: Codable {
    let calendarDate: String // "2024-12-04"
    let steps: Int?
    let distanceInMeters: Int?
    let activeTimeInSeconds: Int?
    let activeKilocalories: Int?
    let bmrKilocalories: Int? // Basal metabolic rate
    let stressLevel: Int? // Average stress (0-100)
    let bodyBatteryChargedValue: Int? // Body Battery at end of day
    let bodyBatteryDrainedValue: Int? // Body Battery at start of day
    let bodyBatteryHighestValue: Int?
    let bodyBatteryLowestValue: Int?
    let restingHeartRate: Int? // bpm
    let hrVariability: Int? // HRV in ms (from sleep)
}

struct GarminSleepData: Codable {
    let calendarDate: String
    let sleepTimeSeconds: Int?
    let deepSleepSeconds: Int?
    let lightSleepSeconds: Int?
    let remSleepSeconds: Int?
    let awakeSleepSeconds: Int?
    let sleepQualityScore: Int? // 0-100
}

struct GarminBodyComposition: Codable {
    let date: String
    let weight: Double? // kg
    let bodyFatPercentage: Double?
    let muscleMass: Double? // kg
    let bodyWaterPercentage: Double?
    let boneMass: Double? // kg
}

// MARK: - Garmin Wellness Sync Manager

@MainActor
class GarminWellnessSync: ObservableObject {
    @Published var isSyncing = false
    @Published var syncStatus: String = ""
    @Published var lastSyncDate: Date?
    
    private let wellnessManager = WellnessManager.shared
    
    /// Syncs wellness data from Garmin Connect
    func syncFromGarmin(
        garminService: GarminService,
        days: Int = 7
    ) async {
        guard !isSyncing else { return }
        guard garminService.isAuthenticated else {
            syncStatus = "Garmin not connected"
            return
        }
        
        isSyncing = true
        syncStatus = "Syncing wellness from Garmin..."
        
        do {
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!
            
            print("🏥 Garmin Wellness: Syncing \(days) days...")
            
            // FIX: Fetch one day at a time (Garmin limit is 24 hours)
            var allSummaries: [GarminDailySummary] = []
            var allSleep: [GarminSleepData] = []
            
            var currentDate = startDate
            let calendar = Calendar.current
            
            while currentDate <= endDate {
                let dayStart = calendar.startOfDay(for: currentDate)
                guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
                
                // Fetch this day's data
                async let dailySummaries = garminService.fetchDailySummaries(startDate: dayStart, endDate: dayEnd)
                async let sleepData = garminService.fetchSleepData(startDate: dayStart, endDate: dayEnd)
                
                let (summaries, sleep) = try await (dailySummaries, sleepData)
                
                allSummaries.append(contentsOf: summaries)
                allSleep.append(contentsOf: sleep)
                
                currentDate = dayEnd
            }
            
            // Body composition doesn't have the same limit, fetch all at once
            let bodyComp = try await garminService.fetchBodyComposition(startDate: startDate, endDate: endDate)
            
            // Convert to DailyWellnessMetrics
            var metricsDict: [Date: DailyWellnessMetrics] = [:]
            
            // Process daily summaries
            for summary in allSummaries {
                guard let date = parseGarminDate(summary.calendarDate) else { continue }
                let dayStart = calendar.startOfDay(for: date)
                
                var metrics = metricsDict[dayStart] ?? DailyWellnessMetrics(date: dayStart)
                
                metrics.steps = summary.steps
                metrics.activeEnergyBurned = summary.activeKilocalories.map { Double($0) }
                metrics.basalEnergyBurned = summary.bmrKilocalories.map { Double($0) }
                metrics.exerciseMinutes = summary.activeTimeInSeconds.map { $0 / 60 }
                
                metricsDict[dayStart] = metrics
            }
            
            // Process sleep data
            for sleepRecord in allSleep {
                guard let date = parseGarminDate(sleepRecord.calendarDate) else { continue }
                let dayStart = calendar.startOfDay(for: date)
                
                var metrics = metricsDict[dayStart] ?? DailyWellnessMetrics(date: dayStart)
                
                metrics.sleepDeep = sleepRecord.deepSleepSeconds.map { TimeInterval($0) }
                metrics.sleepREM = sleepRecord.remSleepSeconds.map { TimeInterval($0) }
                metrics.sleepCore = sleepRecord.lightSleepSeconds.map { TimeInterval($0) }
                metrics.sleepAwake = sleepRecord.awakeSleepSeconds.map { TimeInterval($0) }
                
                metricsDict[dayStart] = metrics
            }
            
            // Process body composition
            for bodyRecord in bodyComp {
                guard let date = parseGarminDate(bodyRecord.date) else { continue }
                let dayStart = calendar.startOfDay(for: date)
                
                var metrics = metricsDict[dayStart] ?? DailyWellnessMetrics(date: dayStart)
                
                metrics.bodyMass = bodyRecord.weight
                metrics.bodyFatPercentage = bodyRecord.bodyFatPercentage.map { $0 / 100 }
                metrics.leanBodyMass = bodyRecord.muscleMass
                
                metricsDict[dayStart] = metrics
            }
            
            // Update wellness manager
            let allMetrics = Array(metricsDict.values).sorted { $0.date < $1.date }
            await MainActor.run {
                wellnessManager.updateBulkMetrics(allMetrics)
                lastSyncDate = Date()
                saveSyncDate()
                syncStatus = "✅ Synced \(allMetrics.count) days from Garmin"
                print("🏥 Garmin Wellness: Synced \(allMetrics.count) days")
            }
            
        } catch {
            syncStatus = "Garmin wellness sync failed: \(error.localizedDescription)"
            print("❌ Garmin wellness sync error: \(error)")
        }
        
        isSyncing = false
    }
    
    // MARK: - Helper Methods
    
    private func parseGarminDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: dateString)
    }
    
    private func saveSyncDate() {
        if let date = lastSyncDate {
            UserDefaults.standard.set(date, forKey: "garminWellnessLastSync")
        }
    }
    
    func loadSyncDate() {
        lastSyncDate = UserDefaults.standard.object(forKey: "garminWellnessLastSync") as? Date
    }
    
    var needsSync: Bool {
        guard let lastSync = lastSyncDate else { return true }
        return Date().timeIntervalSince(lastSync) > 3600 // 1 hour
    }
}

// MARK: - Garmin Service Extensions

extension GarminService {
    
    /// Fetches daily summaries from Garmin Connect
    // In GarminWellnessAdapter.swift, update fetchDailySummaries:

    func fetchDailySummaries(startDate: Date, endDate: Date) async throws -> [GarminDailySummary] {
        try await refreshTokenIfNeededAsync()
        
        guard let token = currentTokens?.accessToken else {
            throw GarminError.notAuthenticated
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        
        let startString = formatter.string(from: startDate)
        let endString = formatter.string(from: endDate)
        
        // FIX: Use correct Garmin wellness endpoint format
        let urlString = "https://apis.garmin.com/wellness-api/rest/dailies?uploadStartTimeInSeconds=\(Int(startDate.timeIntervalSince1970))&uploadEndTimeInSeconds=\(Int(endDate.timeIntervalSince1970))"
        
        guard let url = URL(string: urlString) else {
            throw GarminError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("GarminService: Fetching dailies from \(urlString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarminError.invalidResponse
        }
        
        // Print response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("GarminService: Response (\(httpResponse.statusCode)): \(responseString.prefix(200))")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw GarminError.apiError(statusCode: httpResponse.statusCode, message: "Failed to fetch daily summaries")
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        // Garmin returns array format for this endpoint
        let summaries = try decoder.decode([GarminDailySummary].self, from: data)
        print("GarminService: Fetched \(summaries.count) daily summaries")
        return summaries
    }

    // Update fetchSleepData similarly:
    func fetchSleepData(startDate: Date, endDate: Date) async throws -> [GarminSleepData] {
        try await refreshTokenIfNeededAsync()
        
        guard let token = currentTokens?.accessToken else {
            throw GarminError.notAuthenticated
        }
        
        // FIX: Use Unix timestamps instead of date strings
        let urlString = "https://apis.garmin.com/wellness-api/rest/sleeps?uploadStartTimeInSeconds=\(Int(startDate.timeIntervalSince1970))&uploadEndTimeInSeconds=\(Int(endDate.timeIntervalSince1970))"
        
        guard let url = URL(string: urlString) else {
            throw GarminError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("GarminService: Fetching sleep from \(urlString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarminError.invalidResponse
        }
        
        // Print for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("GarminService: Sleep response (\(httpResponse.statusCode)): \(responseString.prefix(200))")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            print("GarminService: Sleep data not available (status \(httpResponse.statusCode))")
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let sleepData = try decoder.decode([GarminSleepData].self, from: data)
        
        print("GarminService: Fetched \(sleepData.count) sleep records")
        return sleepData
    }

    /// Fetches body composition data from Garmin Connect
    func fetchBodyComposition(startDate: Date, endDate: Date) async throws -> [GarminBodyComposition] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let startString = formatter.string(from: startDate)
        let endString = formatter.string(from: endDate)
        
        let urlString = "https://connect.garmin.com/modern/proxy/weight-service/weight/dateRange?startDate=\(startString)&endDate=\(endString)"
        
        guard let url = URL(string: urlString) else {
            throw GarminError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            // Body composition might not be available - return empty array
            return []
        }
        
        let bodyComp = try JSONDecoder().decode([GarminBodyComposition].self, from: data)
        print("🏥 Garmin: Fetched \(bodyComp.count) body composition records")
        return bodyComp
    }
}

enum GarminError: Error {
    case invalidURL
    case apiError(String)
}

