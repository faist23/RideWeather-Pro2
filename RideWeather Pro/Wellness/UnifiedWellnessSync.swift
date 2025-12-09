//
//  UnifiedWellnessSync.swift
//  RideWeather Pro
//
//  Fetches wellness data from Garmin Connect
//

import Foundation
import HealthKit
import Combine
import UIKit

// Make it @MainActor and ObservableObject
@MainActor
class UnifiedWellnessSync: ObservableObject {
    private let healthStore = HKHealthStore()
    private let wellnessService = WellnessDataService()
    
    // Published properties for UI binding
    @Published var isSyncing = false
    @Published var syncStatus = ""
    @Published var lastSyncDate: Date?
    @Published var needsSync = true
    
    private let syncDateKey = "lastWellnessSyncDate"
    
    init() {
        loadSyncDate()
    }
    
    func loadSyncDate() {
        if let date = UserDefaults.standard.object(forKey: syncDateKey) as? Date {
            lastSyncDate = date
            // Need sync if last sync was more than 12 hours ago
            needsSync = Date().timeIntervalSince(date) > 12 * 3600
        }
    }
    
    private func saveSyncDate() {
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: syncDateKey)
        needsSync = false
    }
    
    // Sync wellness data from configured source
    func syncWellnessData(source: DataSource, userId: String) async throws {
        print("🏥 \(source.rawValue) Wellness: Starting sync...")
        
        switch source {
        case .appleHealth:
            try await syncAppleHealthWellness()
            
        case .garmin:
            // Garmin data is now synced automatically via webhook to Supabase
            // We just fetch the latest data from Supabase
            try await syncGarminWellnessFromSupabase(userId: userId)
            
        case .manual:
            print("⚠️ Manual entry not implemented for wellness")
            
        case .strava:
            print("⚠️ Strava entry not implemented for wellness")
        case .wahoo:
            print("⚠️ Wahoo entry not implemented for wellness")
        }
    }
    
    // MARK: - User Identification
    
    /// Returns a unique identifier for this device/user
    private var appUserId: String {
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            return vendorId
        }
        
        // Fallback: Create and store a UUID if vendorId is unavailable
        let fallbackKey = "app_user_id_fallback"
        if let stored = UserDefaults.standard.string(forKey: fallbackKey) {
            return stored
        }
        
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: fallbackKey)
        return newId
    }
    
    // New unified sync method
    func syncFromConfiguredSource(
        healthManager: HealthKitManager,
        garminService: GarminService,
        days: Int = 7
    ) async {
        guard !isSyncing else { return }
        
        // 1. Fetch the Source of Truth
        let config = DataSourceManager.shared.configuration
        
        // 2. UX: Immediate feedback
        isSyncing = true
        defer {
            isSyncing = false
            saveSyncDate()
        }
        
        do {
            // 3. Switch based on CONFIGURATION, not just authentication status
            switch config.wellnessSource {
            case .garmin:
                guard garminService.isAuthenticated else {
                    syncStatus = "Garmin selected but not connected."
                    return
                }
                syncStatus = "Syncing wellness from Garmin..."
                try await syncWellnessData(source: .garmin, userId: appUserId)
                
            case .appleHealth:
                guard healthManager.isAuthorized else {
                    syncStatus = "Apple Health selected but permissions missing."
                    return
                }
                syncStatus = "Syncing wellness from Apple Health..."
                try await syncWellnessData(source: .appleHealth, userId: "")
                
            case .none:
                syncStatus = "Wellness sync disabled."
                return
            }
            
            syncStatus = "Wellness sync complete!"
            print("✅ Wellness sync completed using source: \(config.wellnessSource.rawValue)")
            
        } catch {
            syncStatus = "Sync failed: \(error.localizedDescription)"
            print("❌ Wellness sync failed: \(error)")
        }
    }
    
    // MARK: - Garmin via Supabase
    private func syncGarminWellnessFromSupabase(userId: String) async throws {
        print("📥 Fetching Garmin wellness data from Supabase...")
        
        // Fetch all wellness data types in parallel
        async let dailies = wellnessService.fetchDailySummaries(forUser: userId, days: 7)
        async let sleep = wellnessService.fetchSleepData(forUser: userId, days: 7)
        async let stress = wellnessService.fetchStressData(forUser: userId, days: 7)
        
        let (dailyData, sleepData, stressData) = try await (dailies, sleep, stress)
        
        print("✅ Fetched from Supabase:")
        print("   - \(dailyData.count) daily summaries")
        print("   - \(sleepData.count) sleep records")
        print("   - \(stressData.count) stress records")
        
        // Process and store the data
        try await processDailyData(dailyData)
        try await processSleepData(sleepData)
        try await processStressData(stressData)
        
        print("✨ Garmin wellness sync complete")
    }
    
    private func processDailyData(_ summaries: [DailySummary]) async throws {
        // Convert to your app's wellness model and store
        for summary in summaries {
            // Use the ISO8601DateFormatter to parse the date
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withFullDate]
            
            guard let date = dateFormatter.date(from: summary.calendarDate) else {
                print("⚠️ Failed to parse date: \(summary.calendarDate)")
                continue
            }
            
            let wellness = WellnessMetrics(
                date: date,
                steps: summary.steps,
                activeCalories: summary.activeKilocalories,
                distance: summary.distanceInMeters,
                averageHR: summary.averageHeartRate,
                restingHR: summary.restingHeartRate,
                source: .garmin
            )
            
            // Save to your local database/storage
            try await saveWellnessMetrics(wellness)
        }
    }
    
    private func processSleepData(_ summaries: [SleepSummary]) async throws {
        for summary in summaries {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withFullDate]
            
            guard let date = dateFormatter.date(from: summary.calendarDate) else {
                print("⚠️ Failed to parse date: \(summary.calendarDate)")
                continue
            }
            
            let sleep = SleepData(
                date: date,
                totalDuration: TimeInterval(summary.durationInSeconds ?? 0),
                deepSleep: TimeInterval(summary.deepSleepDurationInSeconds ?? 0),
                lightSleep: TimeInterval(summary.lightSleepDurationInSeconds ?? 0),
                remSleep: TimeInterval(summary.remSleepInSeconds ?? 0),
                awake: TimeInterval(summary.awakeDurationInSeconds ?? 0),
                source: .garmin
            )
            
            try await saveSleepData(sleep)
        }
    }
    
    private func processStressData(_ summaries: [StressSummary]) async throws {
        for summary in summaries {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withFullDate]
            
            guard let date = dateFormatter.date(from: summary.calendarDate) else {
                print("⚠️ Failed to parse date: \(summary.calendarDate)")
                continue
            }
            
            let stress = StressData(
                date: date,
                averageStress: summary.averageStressLevel,
                maxStress: summary.maxStressLevel,
                restDuration: TimeInterval(summary.restStressDuration ?? 0),
                lowDuration: TimeInterval(summary.lowStressDuration ?? 0),
                mediumDuration: TimeInterval(summary.mediumStressDuration ?? 0),
                highDuration: TimeInterval(summary.highStressDuration ?? 0),
                source: .garmin
            )
            
            try await saveStressData(stress)
        }
    }
    
    // MARK: - Apple Health
    private func syncAppleHealthWellness() async throws {
        print("🍎 Syncing from Apple Health...")
        
        // Check authorization
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WellnessError.healthKitNotAvailable
        }
        
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -7, to: endDate)!
        
        // Fetch data in parallel
        async let hrv = fetchHRVData(start: startDate, end: endDate)
        async let sleep = fetchSleepAnalysis(start: startDate, end: endDate)
        async let steps = fetchStepsData(start: startDate, end: endDate)
        async let restingHR = fetchRestingHeartRate(start: startDate, end: endDate)
        async let activeEnergy = fetchActiveEnergy(start: startDate, end: endDate)
        
        let (hrvData, sleepData, stepsData, restingHRData, activeEnergyData) = try await (hrv, sleep, steps, restingHR, activeEnergy)
        
        print("✅ Apple Health sync complete")
        print("   - \(hrvData.count) HRV readings")
        print("   - \(sleepData.count) sleep records")
        print("   - \(stepsData.count) step records")
        print("   - \(restingHRData.count) resting HR readings")
        print("   - \(activeEnergyData.count) active energy records")
        
        // Process and save
        try await processAppleHealthData(
            hrv: hrvData,
            sleep: sleepData,
            steps: stepsData,
            restingHR: restingHRData,
            activeEnergy: activeEnergyData
        )
    }
    
    private func fetchHRVData(start: Date, end: Date) async throws -> [HRVSample] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return []
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let hrvSamples = (samples as? [HKQuantitySample])?.map { sample in
                    HRVSample(
                        date: sample.startDate,
                        value: sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                    )
                } ?? []
                
                continuation.resume(returning: hrvSamples)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchSleepAnalysis(start: Date, end: Date) async throws -> [SleepAnalysisSample] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let sleepSamples = (samples as? [HKCategorySample])?.map { sample in
                    SleepAnalysisSample(
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        value: sample.value
                    )
                } ?? []
                
                continuation.resume(returning: sleepSamples)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchStepsData(start: Date, end: Date) async throws -> [StepSample] {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return []
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepsType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1)
            )
            
            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                var samples: [StepSample] = []
                results?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        samples.append(StepSample(
                            date: statistics.startDate,
                            steps: Int(sum.doubleValue(for: HKUnit.count()))
                        ))
                    }
                }
                
                continuation.resume(returning: samples)
            }
            
            healthStore.execute(query)
        }
    }
    
    private func fetchRestingHeartRate(start: Date, end: Date) async throws -> [RestingHRSample] {
        guard let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            return []
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: restingHRType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let hrSamples = (samples as? [HKQuantitySample])?.map { sample in
                    RestingHRSample(
                        date: sample.startDate,
                        bpm: Int(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute())))
                    )
                } ?? []
                
                continuation.resume(returning: hrSamples)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchActiveEnergy(start: Date, end: Date) async throws -> [ActiveEnergySample] {
        guard let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return []
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: activeEnergyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1)
            )
            
            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                var samples: [ActiveEnergySample] = []
                results?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        samples.append(ActiveEnergySample(
                            date: statistics.startDate,
                            calories: Int(sum.doubleValue(for: HKUnit.kilocalorie()))
                        ))
                    }
                }
                
                continuation.resume(returning: samples)
            }
            
            healthStore.execute(query)
        }
    }
    
    private func processAppleHealthData(
        hrv: [HRVSample],
        sleep: [SleepAnalysisSample],
        steps: [StepSample],
        restingHR: [RestingHRSample],
        activeEnergy: [ActiveEnergySample]
    ) async throws {
        // Group by date and save
        let calendar = Calendar.current
        var dataByDate: [Date: (steps: Int?, restingHR: Int?, activeCalories: Int?, hrv: Double?)] = [:]
        
        // Group steps by date
        for sample in steps {
            let date = calendar.startOfDay(for: sample.date)
            var existing = dataByDate[date] ?? (nil, nil, nil, nil)
            existing.steps = sample.steps
            dataByDate[date] = existing
        }
        
        // Group resting HR by date
        for sample in restingHR {
            let date = calendar.startOfDay(for: sample.date)
            var existing = dataByDate[date] ?? (nil, nil, nil, nil)
            existing.restingHR = sample.bpm
            dataByDate[date] = existing
        }
        
        // Group active energy by date
        for sample in activeEnergy {
            let date = calendar.startOfDay(for: sample.date)
            var existing = dataByDate[date] ?? (nil, nil, nil, nil)
            existing.activeCalories = sample.calories
            dataByDate[date] = existing
        }
        
        // Group HRV by date (take average for the day)
        var hrvByDate: [Date: [Double]] = [:]
        for sample in hrv {
            let date = calendar.startOfDay(for: sample.date)
            hrvByDate[date, default: []].append(sample.value)
        }
        for (date, values) in hrvByDate {
            var existing = dataByDate[date] ?? (nil, nil, nil, nil)
            existing.hrv = values.reduce(0, +) / Double(values.count)
            dataByDate[date] = existing
        }
        
        // Save wellness metrics
        for (date, data) in dataByDate {
            let wellness = WellnessMetrics(
                date: date,
                steps: data.steps,
                activeCalories: data.activeCalories,
                distance: nil,
                averageHR: nil,
                restingHR: data.restingHR,
                source: .appleHealth
            )
            try await saveWellnessMetrics(wellness)
        }
        
        // Process sleep data
        for sample in sleep {
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            
            // Map HKCategoryValueSleepAnalysis to sleep stages
            var deepSleep: TimeInterval = 0
            var lightSleep: TimeInterval = 0
            var remSleep: TimeInterval = 0
            var awake: TimeInterval = 0
            
            switch sample.value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                deepSleep = duration
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                 HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                lightSleep = duration
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                remSleep = duration
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                awake = duration
            default:
                break
            }
            
            let sleepData = SleepData(
                date: calendar.startOfDay(for: sample.startDate),
                totalDuration: duration,
                deepSleep: deepSleep,
                lightSleep: lightSleep,
                remSleep: remSleep,
                awake: awake,
                source: .appleHealth
            )
            
            try await saveSleepData(sleepData)
        }
    }
    
    // MARK: - Storage Methods (implement based on your data persistence layer)
    private func saveWellnessMetrics(_ metrics: WellnessMetrics) async throws {
        // TODO: Save to your local database/CoreData/SwiftData
        print("💾 Saving wellness metrics for \(metrics.date)")
    }
    
    private func saveSleepData(_ data: SleepData) async throws {
        // TODO: Save to your local database
        print("💾 Saving sleep data for \(data.date)")
    }
    
    private func saveStressData(_ data: StressData) async throws {
        // TODO: Save to your local database
        print("💾 Saving stress data for \(data.date)")
    }
}

// MARK: - Models
struct WellnessMetrics {
    let date: Date
    let steps: Int?
    let activeCalories: Int?
    let distance: Double?
    let averageHR: Int?
    let restingHR: Int?
    let source: DataSource
}

struct SleepData {
    let date: Date
    let totalDuration: TimeInterval
    let deepSleep: TimeInterval
    let lightSleep: TimeInterval
    let remSleep: TimeInterval
    let awake: TimeInterval
    let source: DataSource
}

struct StressData {
    let date: Date
    let averageStress: Int?
    let maxStress: Int?
    let restDuration: TimeInterval
    let lowDuration: TimeInterval
    let mediumDuration: TimeInterval
    let highDuration: TimeInterval
    let source: DataSource
}

// Apple Health Sample Types
struct HRVSample {
    let date: Date
    let value: Double
}

struct SleepAnalysisSample {
    let startDate: Date
    let endDate: Date
    let value: Int
}

struct StepSample {
    let date: Date
    let steps: Int
}

struct RestingHRSample {
    let date: Date
    let bpm: Int
}

struct ActiveEnergySample {
    let date: Date
    let calories: Int
}

enum WellnessError: Error {
    case unsupportedSource
    case noData
    case authenticationRequired
    case healthKitNotAvailable
}
