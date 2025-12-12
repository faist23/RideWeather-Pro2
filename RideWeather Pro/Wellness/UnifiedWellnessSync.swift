//
//  UnifiedWellnessSync.swift
//  RideWeather Pro
//
//  Fetches wellness data from Garmin Connect and Apple Health
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
    
    // MARK: - User Identification
    
    private var appUserId: String {
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            return vendorId
        }
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
        
        let config = DataSourceManager.shared.configuration
        
        isSyncing = true
        defer {
            isSyncing = false
            saveSyncDate()
        }
        
        do {
            switch config.wellnessSource {
            case .garmin:
                guard garminService.isAuthenticated else {
                    syncStatus = "Garmin selected but not connected."
                    return
                }
                syncStatus = "Syncing wellness from Garmin..."
                try await syncGarminWellnessFromSupabase(userId: appUserId)
                
            case .appleHealth:
                guard healthManager.isAuthorized else {
                    syncStatus = "Apple Health permissions missing."
                    return
                }
                syncStatus = "Syncing wellness from Apple Health..."
                try await syncAppleHealthWellness()
                
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
        
        async let dailies = wellnessService.fetchDailySummaries(forUser: userId, days: 7)
        async let sleep = wellnessService.fetchSleepData(forUser: userId, days: 7)
        
        let (dailyData, sleepData) = try await (dailies, sleep)
        
        print("✅ Fetched from Supabase: \(dailyData.count) daily, \(sleepData.count) sleep records")
        
        var metricsByDate: [Date: DailyWellnessMetrics] = [:]
        let calendar = Calendar.current
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        
        // 1. Process Daily Summaries
        for summary in dailyData {
            guard let date = dateFormatter.date(from: summary.calendarDate) else { continue }
            let startOfDay = calendar.startOfDay(for: date)
            
            var metric = metricsByDate[startOfDay] ?? DailyWellnessMetrics(date: startOfDay)
            metric.steps = summary.steps
            metric.activeEnergyBurned = summary.activeKilocalories.map { Double($0) }
            metric.restingHeartRate = summary.restingHeartRate
            metric.distance = summary.distanceInMeters
            
            metricsByDate[startOfDay] = metric
        }
        
        // 2. Process Sleep Data
        for summary in sleepData {
            guard let date = dateFormatter.date(from: summary.calendarDate) else { continue }
            let startOfDay = calendar.startOfDay(for: date)
            
            var metric = metricsByDate[startOfDay] ?? DailyWellnessMetrics(date: startOfDay)
            metric.sleepDeep = TimeInterval(summary.deepSleepDurationInSeconds ?? 0)
            metric.sleepREM = TimeInterval(summary.remSleepInSeconds ?? 0)
            metric.sleepCore = TimeInterval(summary.lightSleepDurationInSeconds ?? 0)
            metric.sleepAwake = TimeInterval(summary.awakeDurationInSeconds ?? 0)
            metricsByDate[startOfDay] = metric
        }
        
        let allMetrics = Array(metricsByDate.values)
        if !allMetrics.isEmpty {
            await MainActor.run {
                WellnessManager.shared.updateBulkMetrics(allMetrics)
            }
            print("✨ Garmin wellness sync complete. Saved \(allMetrics.count) days.")
        }
    }
    
    // MARK: - Apple Health
        private func syncAppleHealthWellness() async throws {
            print("🍎 Syncing from Apple Health...")
            
            guard HKHealthStore.isHealthDataAvailable() else {
                throw WellnessError.healthKitNotAvailable
            }
            
            let calendar = Calendar.current
            let endDate = Date()
            let startOfToday = calendar.startOfDay(for: endDate)
            let startDate = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
            
            // Fetch data
            async let hrv = fetchHRVData(start: startDate, end: endDate)
            async let sleep = fetchSleepAnalysis(start: startDate, end: endDate)
            async let steps = fetchStepsData(start: startDate, end: endDate)
            async let restingHR = fetchRestingHeartRate(start: startDate, end: endDate)
            async let activeEnergy = fetchActiveEnergy(start: startDate, end: endDate)
            async let bodyMass = fetchBodyMass(start: startDate, end: endDate)
            
            let (hrvData, sleepData, stepsData, restingHRData, activeEnergyData, bodyMassData) = try await (hrv, sleep, steps, restingHR, activeEnergy, bodyMass)
            
            // ---------------------------------------------------------------------
            // 1. NON-SLEEP DATA (Standard Daily Grouping)
            // ---------------------------------------------------------------------
            var metricsByDate: [Date: DailyWellnessMetrics] = [:]
            
            func getMetric(for date: Date) -> DailyWellnessMetrics {
                let startOfDay = calendar.startOfDay(for: date)
                return metricsByDate[startOfDay] ?? DailyWellnessMetrics(date: startOfDay)
            }
            
            for sample in stepsData {
                var metric = getMetric(for: sample.date)
                metric.steps = sample.steps
                metricsByDate[metric.date] = metric
            }
            for sample in activeEnergyData {
                var metric = getMetric(for: sample.date)
                metric.activeEnergyBurned = Double(sample.calories)
                metricsByDate[metric.date] = metric
            }
            for sample in bodyMassData {
                var metric = getMetric(for: sample.date)
                metric.bodyMass = sample.value
                metricsByDate[metric.date] = metric
            }
            for sample in restingHRData {
                var metric = getMetric(for: sample.date)
                metric.restingHeartRate = sample.bpm
                metricsByDate[metric.date] = metric
            }
            
            // ---------------------------------------------------------------------
            // 2. SLEEP DATA (Smart "Sleep Night" Grouping & Explicit Source Selection)
            // ---------------------------------------------------------------------
            // Logic: Shift time +6 hours to assign "Night of 12/9" to "12/10".
            let sleepBySleepDay = Dictionary(grouping: sleepData) { sample in
                let adjustedDate = sample.startDate.addingTimeInterval(6 * 3600)
                return calendar.startOfDay(for: adjustedDate)
            }
            
            print("\n😴 Sleep Processing:")
            
            for (date, allSamples) in sleepBySleepDay {
                var metric = getMetric(for: date)
                
                // --- SOURCE FILTERING FIX ---
                // 1. Identify if AutoSleep is present (using strict bundle ID check)
                let hasAutoSleep = allSamples.contains { $0.sourceBundleId.lowercased().contains("autosleep") }
                
                let targetSamples: [SleepAnalysisSample]
                let usedSource: String
                
                if hasAutoSleep {
                    // ✅ AutoSleep Mode: Use ONLY AutoSleep samples
                    targetSamples = allSamples.filter { $0.sourceBundleId.lowercased().contains("autosleep") }
                    usedSource = "AutoSleep"
                } else {
                    // ⌚️ Apple Watch Mode: Use everything else (likely Apple Watch)
                    targetSamples = allSamples
                    usedSource = "Apple Watch"
                }
                
                // --- STAGE FILTERING ---
                // Important: AutoSleep writes "In Bed" (0) and "Asleep" (1). We MUST ignore 0.
                // "Unspecified" (1) from AutoSleep is treated as "Core" here to ensure it counts as sleep.
                
                let deepSamples = targetSamples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
                let remSamples = targetSamples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue }
                let coreSamples = targetSamples.filter {
                    $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue // <-- AutoSleep "Asleep" falls here
                }
                let awakeSamples = targetSamples.filter { $0.value == HKCategoryValueSleepAnalysis.awake.rawValue }
                
                // Calculate unique duration for each stage
                metric.sleepDeep = calculateUniqueDuration(deepSamples)
                metric.sleepREM = calculateUniqueDuration(remSamples)
                metric.sleepCore = calculateUniqueDuration(coreSamples)
                metric.sleepAwake = calculateUniqueDuration(awakeSamples)
                
                let totalSleep = (metric.sleepDeep ?? 0) + (metric.sleepCore ?? 0) + (metric.sleepREM ?? 0)
                
                print("   👉 \(date.formatted(date: .numeric, time: .omitted)): \(String(format: "%.1f", totalSleep/3600))h | Source: \(usedSource)")
                
                metricsByDate[metric.date] = metric
            }
            
            // ---------------------------------------------------------------------
            // 3. SAVE
            // ---------------------------------------------------------------------
            let allMetrics = Array(metricsByDate.values)
            if !allMetrics.isEmpty {
                await MainActor.run {
                    WellnessManager.shared.updateBulkMetrics(allMetrics)
                }
                print("💾 Saved \(allMetrics.count) days of wellness data.")
            }
        }
    
    /// Merges overlapping sleep intervals to prevent double counting (e.g. AutoSleep + Apple Watch)
    private func calculateUniqueDuration(_ samples: [SleepAnalysisSample]) -> TimeInterval {
        guard !samples.isEmpty else { return 0 }
        
        // 1. Sort by start time
        let sortedSamples = samples.sorted { $0.startDate < $1.startDate }
        
        var totalDuration: TimeInterval = 0
        // Start with the first interval
        var currentIntervalStart = sortedSamples[0].startDate
        var currentIntervalEnd = sortedSamples[0].endDate
        
        for i in 1..<sortedSamples.count {
            let nextSample = sortedSamples[i]
            
            if nextSample.startDate < currentIntervalEnd {
                // Overlap detected: Extend current interval if needed
                if nextSample.endDate > currentIntervalEnd {
                    currentIntervalEnd = nextSample.endDate
                }
            } else {
                // No overlap: Commit the current interval and start a new one
                totalDuration += currentIntervalEnd.timeIntervalSince(currentIntervalStart)
                currentIntervalStart = nextSample.startDate
                currentIntervalEnd = nextSample.endDate
            }
        }
        
        // Commit the final interval
        totalDuration += currentIntervalEnd.timeIntervalSince(currentIntervalStart)
        
        return totalDuration
    }
    
    // MARK: - HealthKit Fetchers
    
    private func fetchHRVData(start: Date, end: Date) async throws -> [HRVSample] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        return try await fetchSamples(type: hrvType, start: start, end: end).map {
            HRVSample(date: $0.startDate, value: $0.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)))
        }
    }
    
    private func fetchBodyMass(start: Date, end: Date) async throws -> [BodyMassSample] {
        guard let massType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return [] }
        return try await fetchSamples(type: massType, start: start, end: end).map {
            BodyMassSample(date: $0.startDate, value: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
        }
    }
    
    private func fetchSleepAnalysis(start: Date, end: Date) async throws -> [SleepAnalysisSample] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error { continuation.resume(throwing: error); return }
                let sleepSamples = (samples as? [HKCategorySample])?.map { sample in
                    SleepAnalysisSample(
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        value: sample.value,
                        sourceBundleId: sample.sourceRevision.source.bundleIdentifier
                    )
                } ?? []
                continuation.resume(returning: sleepSamples)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchStepsData(start: Date, end: Date) async throws -> [StepSample] {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [] }
        return try await fetchDailyStatistics(type: stepsType, start: start, end: end, unit: .count()) {
            StepSample(date: $0.startDate, steps: Int($1.doubleValue(for: .count())))
        }
    }
    
    private func fetchRestingHeartRate(start: Date, end: Date) async throws -> [RestingHRSample] {
        guard let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return [] }
        return try await fetchSamples(type: restingHRType, start: start, end: end).map {
            RestingHRSample(date: $0.startDate, bpm: Int($0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))))
        }
    }
    
    private func fetchActiveEnergy(start: Date, end: Date) async throws -> [ActiveEnergySample] {
        guard let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return [] }
        return try await fetchDailyStatistics(type: activeEnergyType, start: start, end: end, unit: .kilocalorie()) {
            ActiveEnergySample(date: $0.startDate, calories: Int($1.doubleValue(for: .kilocalorie())))
        }
    }
    
    // MARK: - Generic HealthKit Helpers
    
    private func fetchSamples(type: HKSampleType, start: Date, end: Date) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }
    
    // Updated to align with Day Boundaries for correct daily totals
    private func fetchDailyStatistics<T>(type: HKQuantityType, start: Date, end: Date, unit: HKUnit, transform: @escaping (HKStatistics, HKQuantity) -> T) async throws -> [T] {
        let calendar = Calendar.current
        // Anchor to Midnight to ensure daily buckets are 00:00 - 23:59
        let anchorDate = calendar.startOfDay(for: start)
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate, // ✅ Fixed anchor
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, error in
                if let error = error { continuation.resume(throwing: error); return }
                var samples: [T] = []
                results?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        samples.append(transform(statistics, sum))
                    }
                }
                continuation.resume(returning: samples)
            }
            healthStore.execute(query)
        }
    }
}

// MARK: - Helper Structs
struct HRVSample { let date: Date; let value: Double }

struct SleepAnalysisSample {
    let startDate: Date
    let endDate: Date
    let value: Int
    let sourceBundleId: String
}

struct StepSample { let date: Date; let steps: Int }
struct RestingHRSample { let date: Date; let bpm: Int }
struct ActiveEnergySample { let date: Date; let calories: Int }
struct BodyMassSample { let date: Date; let value: Double }

enum WellnessError: Error {
    case unsupportedSource
    case noData
    case authenticationRequired
    case healthKitNotAvailable
}
