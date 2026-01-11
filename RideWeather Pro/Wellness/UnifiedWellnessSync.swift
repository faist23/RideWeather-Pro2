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
        print("🔧 UnifiedWellnessSync: Initialized")
    }
    
    func loadSyncDate() {
        if let date = UserDefaults.standard.object(forKey: syncDateKey) as? Date {
            lastSyncDate = date
            needsSync = Date().timeIntervalSince(date) > 12 * 3600
            print("📅 Last wellness sync: \(date.formatted(date: .abbreviated, time: .shortened))")
            print("📊 Needs sync: \(needsSync)")
        } else {
            print("⚠️ No previous sync date found")
        }
    }
    
    private func saveSyncDate() {
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: syncDateKey)
        needsSync = false
        print("✅ Sync date saved: \(lastSyncDate!.formatted(date: .abbreviated, time: .shortened))")
    }

    // MARK: - User Identification    
    private var appUserId: String {
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            print("👤 Using vendor ID: \(vendorId)")
            return vendorId
        }
        let fallbackKey = "app_user_id_fallback"
        if let stored = UserDefaults.standard.string(forKey: fallbackKey) {
            print("👤 Using stored fallback ID: \(stored)")
            return stored
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: fallbackKey)
        print("👤 Generated new fallback ID: \(newId)")
        return newId
    }
    
    // MARK: - Unified Sync Method
    
    func syncFromConfiguredSource(
        healthManager: HealthKitManager,
        garminService: GarminService,
        days: Int = 7
    ) async {
        print("\n" + String(repeating: "=", count: 60))
        print("🔄 WELLNESS SYNC STARTED")
        print(String(repeating: "=", count: 60))
        
        guard !isSyncing else {
            print("⚠️ Sync already in progress, skipping")
            return
        }
        
        let config = DataSourceManager.shared.configuration
        print("📋 Data source configuration:")
        print("   - Wellness source: \(config.wellnessSource.rawValue)")
        print("   - Training source: \(config.trainingLoadSource.rawValue)")
        print("   - Days to sync: \(days)")
        
        isSyncing = true
        defer {
            isSyncing = false
            saveSyncDate()
            print("\n" + String(repeating: "=", count: 60))
            print("🏁 WELLNESS SYNC COMPLETED")
            print(String(repeating: "=", count: 60) + "\n")
        }
        
        do {
            switch config.wellnessSource {
            case .garmin:
                try await syncGarminWellnessFromSupabase(userId: appUserId)
                
                // ✅ UPDATE WEIGHT from Garmin data
                await updateWeightFromLatestMetrics()
                
            case .appleHealth:
                try await syncAppleHealthWellness()
                
                // ✅ UPDATE WEIGHT from Apple Health data
                await updateWeightFromLatestMetrics()
                
            case .none:
                return
            }
            
            syncStatus = "Wellness sync complete!"
            print("\n✅ Sync completed successfully")
            print("   Source: \(config.wellnessSource.rawValue)")
            
        } catch {
            let errorMsg = "Sync failed: \(error.localizedDescription)"
            syncStatus = errorMsg
            print("\n❌ SYNC FAILED")
            print("   Error: \(error)")
            print("   Localized: \(error.localizedDescription)")
            
            if let wellnessError = error as? WellnessError {
                print("   Type: WellnessError")
                print("   Details: \(wellnessError)")
            }
        }
    }
    
    // ✅ ADD NEW METHOD to update app weight from synced metrics
    private func updateWeightFromLatestMetrics() async {
        await MainActor.run {
            // Get the most recent weight from wellness metrics
            if let latestWeight = WellnessManager.shared.dailyMetrics
                .sorted(by: { $0.date > $1.date })
                .first(where: { $0.bodyMass != nil })?.bodyMass {
                
                // Update the app settings
                let settings = UserDefaultsManager.shared.loadSettings()
                var updatedSettings = settings
                updatedSettings.bodyWeight = latestWeight
                UserDefaultsManager.shared.saveSettings(updatedSettings)
                
                print("✅ Updated weight from wellness metrics: \(latestWeight) kg")
            }
        }
    }
    
    // MARK: - Garmin via Supabase
    
    private func syncGarminWellnessFromSupabase(userId: String) async throws {
         print("\n📥 GARMIN SUPABASE SYNC")
         print(String(repeating: "-", count: 40))
         print("App User ID: \(userId)")
         
         // Step 0: Get Garmin User ID from mapping table
         print("\n🔍 Looking up Garmin User ID from user_garmin_mapping...")
         
         guard let garminUserId = try await wellnessService.getGarminUserId(forAppUser: userId) else {
             print("❌ No Garmin user mapping found for app user: \(userId)")
             print("\n⚠️ DIAGNOSIS:")
             print("   The user_garmin_mapping table doesn't have an entry for this user.")
             print("   This happens when:")
             print("   1. User hasn't completed Garmin OAuth yet")
             print("   2. linkToSupabase() wasn't called after OAuth")
             print("   3. The mapping was deleted/cleared")
             print("\n💡 SOLUTION:")
             print("   Re-authenticate with Garmin to create the mapping.")
             throw WellnessError.authenticationRequired
         }
         
         print("✅ Found Garmin User ID: \(garminUserId)")
         
         // Step 1: Fetch data from Supabase using GARMIN user ID
         print("\n🔍 Fetching wellness data from Supabase...")
         print("   Querying with garmin_user_id: \(garminUserId)")
         
         do {
             // Pass the garminUserId to the fetch methods
             async let dailies = wellnessService.fetchDailySummaries(forUser: userId, garminUserId: garminUserId, days: 7)
             async let sleep = wellnessService.fetchSleepData(forUser: userId, garminUserId: garminUserId, days: 7)
             async let bodyComps = wellnessService.fetchBodyComposition(forUser: userId, garminUserId: garminUserId, days: 30) // Fetch more days for weight

             let (dailyData, sleepData, bodyCompData) = try await (dailies, sleep, bodyComps)

             print("✅ Supabase fetch successful:")
             print("   - Daily summaries: \(dailyData.count)")
             print("   - Sleep records: \(sleepData.count)")
             
             if dailyData.isEmpty && sleepData.isEmpty {
                 print("\n⚠️ WARNING: No data returned from Supabase")
                 print("   garmin_user_id: \(garminUserId)")
                 print("   app_user_id: \(userId)")
                 print("\n   This could mean:")
                 print("   1. Garmin hasn't pushed any wellness data to your backend yet")
                 print("   2. The backend webhook isn't working")
                 print("   3. Data exists but for a different garmin_user_id")
                 print("\n💡 DEBUGGING STEPS:")
                 print("   1. Check Supabase garmin_wellness table directly")
                 print("   2. Verify webhook is receiving Garmin push notifications")
                 print("   3. Check if garmin_user_id matches what's in the table")
                 return
             }
             
             // Step 2: Process the data
             print("\n🔨 Processing fetched data...")
             
             var metricsByDate: [Date: DailyWellnessMetrics] = [:]
             let calendar = Calendar.current
             let dateFormatter = ISO8601DateFormatter()
             dateFormatter.formatOptions = [.withFullDate]
             
             // Process Daily Summaries
             print("\n📊 Processing \(dailyData.count) daily summaries...")
             for (index, summary) in dailyData.enumerated() {
                 print("   [\(index + 1)/\(dailyData.count)] Date: \(summary.calendarDate)")
                 
                 guard let date = dateFormatter.date(from: summary.calendarDate) else {
                     print("      ❌ Failed to parse date: \(summary.calendarDate)")
                     continue
                 }
                 
                 let startOfDay = calendar.startOfDay(for: date)
                 print("      📅 Parsed to: \(startOfDay.formatted(date: .abbreviated, time: .omitted))")
                 
                 var metric = metricsByDate[startOfDay] ?? DailyWellnessMetrics(date: startOfDay)
                 
                 // Log each field
                 if let steps = summary.steps {
                     print("      👣 Steps: \(steps)")
                     metric.steps = steps
                 }
                 
                 if let calories = summary.activeKilocalories {
                     print("      🔥 Active calories: \(calories)")
                     metric.activeEnergyBurned = Double(calories)
                 }
                 
                 if let hr = summary.restingHeartRate {
                     print("      ❤️ Resting HR: \(hr) bpm")
                     metric.restingHeartRate = hr
                 }
                 
                 if let distance = summary.distanceInMeters {
                     print("      📏 Distance: \(String(format: "%.1f", distance / 1000)) km")
                     metric.distance = distance
                 }
                 
                 metricsByDate[startOfDay] = metric
                 print("      ✅ Daily summary processed")
             }
             
             // Process Sleep Data
             print("\n😴 Processing \(sleepData.count) sleep records...")
             for (index, summary) in sleepData.enumerated() {
                 print("   [\(index + 1)/\(sleepData.count)] Date: \(summary.calendarDate)")
                 
                 guard let date = dateFormatter.date(from: summary.calendarDate) else {
                     print("      ❌ Failed to parse date: \(summary.calendarDate)")
                     continue
                 }
                 
                 let startOfDay = calendar.startOfDay(for: date)
                 print("      📅 Parsed to: \(startOfDay.formatted(date: .abbreviated, time: .omitted))")
                 
                 var metric = metricsByDate[startOfDay] ?? DailyWellnessMetrics(date: startOfDay)
                 
                 if let deep = summary.deepSleepDurationInSeconds {
                     let hours = Double(deep) / 3600
                     print("      🌙 Deep sleep: \(String(format: "%.1f", hours))h")
                     metric.sleepDeep = TimeInterval(deep)
                 }
                 
                 if let rem = summary.remSleepInSeconds {
                     let hours = Double(rem) / 3600
                     print("      💭 REM sleep: \(String(format: "%.1f", hours))h")
                     metric.sleepREM = TimeInterval(rem)
                 }
                 
                 if let light = summary.lightSleepDurationInSeconds {
                     let hours = Double(light) / 3600
                     print("      ☁️ Light sleep: \(String(format: "%.1f", hours))h")
                     metric.sleepCore = TimeInterval(light)
                 }
                 
                 if let awake = summary.awakeDurationInSeconds {
                     let hours = Double(awake) / 3600
                     print("      👀 Awake: \(String(format: "%.1f", hours))h")
                     metric.sleepAwake = TimeInterval(awake)
                 }
                 
                 // Calculate total sleep
                 var totalSleep = (metric.sleepDeep ?? 0) + (metric.sleepREM ?? 0) + (metric.sleepCore ?? 0)
                 
                 // If stages sum to 0 but we have total duration (e.g. Manual entries), use total
                 if totalSleep == 0, let duration = summary.durationInSeconds, duration > 0 {
                     print("      ⚠️ Sleep stages missing. Using total duration: \(duration)s")
                     // Assign to Core/Light so it counts towards totals
                     metric.sleepCore = TimeInterval(duration)
                     totalSleep = TimeInterval(duration)
                 }
                 
                 print("      📊 Total sleep: \(String(format: "%.1f", totalSleep / 3600))h")
                 
                 metricsByDate[startOfDay] = metric
                 print("      ✅ Sleep data processed")
             }
             
             // Process Body Composition Data (Weight)
             print("\n⚖️ Processing \(bodyCompData.count) body composition records...")
             for (index, bodyComp) in bodyCompData.enumerated() {
                 print("   [\(index + 1)/\(bodyCompData.count)] Date: \(bodyComp.measurementDate.formatted(date: .abbreviated, time: .shortened))")
                 
                 // Use the measurement date to find the right day
                 let startOfDay = calendar.startOfDay(for: bodyComp.measurementDate)
                 print("      📅 Parsed to: \(startOfDay.formatted(date: .abbreviated, time: .omitted))")
                 
                 var metric = metricsByDate[startOfDay] ?? DailyWellnessMetrics(date: startOfDay)
                 
                 print("      ⚖️ Weight: \(String(format: "%.1f", bodyComp.weightKg)) kg")
                 metric.bodyMass = bodyComp.weightKg
                 
                 if let bmi = bodyComp.bmi {
                     print("      📊 BMI: \(String(format: "%.1f", bmi))")
                 }
                 
                 if let bodyFat = bodyComp.bodyFatPercentage {
                     print("      💪 Body Fat: \(String(format: "%.1f", bodyFat))%")
                 }
                 
                 metricsByDate[startOfDay] = metric
                 print("      ✅ Body composition processed")
             }

             // Print summary
             if !bodyCompData.isEmpty {
                 let avgWeight = bodyCompData.map { $0.weightKg }.reduce(0, +) / Double(bodyCompData.count)
                 print("\n📊 Weight Summary:")
                 print("   - Total measurements: \(bodyCompData.count)")
                 print("   - Average weight: \(String(format: "%.1f", avgWeight)) kg")
                 print("   - Date range: \(bodyCompData.last?.measurementDate.formatted(date: .abbreviated, time: .omitted) ?? "N/A") to \(bodyCompData.first?.measurementDate.formatted(date: .abbreviated, time: .omitted) ?? "N/A")")
             } else {
                 print("\n⚠️ No weight data found in Garmin wellness")
             }

             // Step 3: Save to WellnessManager
             let allMetrics = Array(metricsByDate.values).sorted { $0.date < $1.date }
             
             print("\n💾 Saving \(allMetrics.count) days to WellnessManager...")
             for (index, metric) in allMetrics.enumerated() {
                 print("   [\(index + 1)/\(allMetrics.count)] \(metric.date.formatted(date: .abbreviated, time: .omitted))")
                 print("      Steps: \(metric.steps ?? 0)")
                 if let sleep = metric.totalSleep {
                     print("      Sleep: \(String(format: "%.1f", sleep / 3600))h")
                 }
             }
             
             if !allMetrics.isEmpty {
                 await MainActor.run {
                     WellnessManager.shared.updateBulkMetrics(allMetrics)
                     
                     // 🆕 Notify that wellness data was updated
                     NotificationCenter.default.post(name: .wellnessDataUpdated, object: nil)
                 }
                 print("\n✅ Successfully saved \(allMetrics.count) days to WellnessManager")
             } else {
                 print("\n⚠️ No metrics to save (all dates filtered out)")
             }
             
         } catch {
             print("\n❌ SUPABASE FETCH ERROR")
             print("   Error: \(error)")
             print("   Type: \(type(of: error))")
             print("   Localized: \(error.localizedDescription)")
             throw error
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
        // 2. SLEEP DATA (Smart Fallback Logic)
        // ---------------------------------------------------------------------
        // Logic: Shift time +6 hours to assign "Night of 12/9" to "12/10".
        let sleepBySleepDay = Dictionary(grouping: sleepData) { sample in
            let adjustedDate = sample.startDate.addingTimeInterval(6 * 3600)
            return calendar.startOfDay(for: adjustedDate)
        }
        
        print("\n😴 Sleep Processing:")
        
        for (date, allSamples) in sleepBySleepDay {
            var metric = getMetric(for: date)
            
            // --- SMART SOURCE SELECTION ---
            // 1. Split samples by source
            let autoSleepSamples = allSamples.filter { $0.sourceBundleId.lowercased().contains("autosleep") }
            let otherSamples = allSamples.filter { !$0.sourceBundleId.lowercased().contains("autosleep") }
            
            // 2. Calculate TOTAL sleep duration for each source (ignoring InBed/Awake)
            let autoSleepDuration = calculateTotalSleepDuration(autoSleepSamples)
            let otherDuration = calculateTotalSleepDuration(otherSamples)
            
            let targetSamples: [SleepAnalysisSample]
            let usedSource: String
            
            // 3. Decide which to use
            if autoSleepDuration > 0 {
                // AutoSleep has data -> Use it (prevents double counting)
                targetSamples = autoSleepSamples
                usedSource = "AutoSleep"
            } else if otherDuration > 0 {
                // AutoSleep is 0h (or missing) -> Fallback to Apple Watch
                targetSamples = otherSamples
                usedSource = autoSleepSamples.isEmpty ? "Apple Watch" : "Apple Watch (Fallback)"
                if !autoSleepSamples.isEmpty {
 //                   print("   ⚠️ AutoSleep found but had 0h sleep. Falling back to Apple Watch.")
                }
            } else {
                targetSamples = allSamples
                usedSource = "None/Mixed"
            }
            
            // --- STAGE MAPPING ---
            let deepSamples = targetSamples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
            let remSamples = targetSamples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue }
            
            // Map "Unspecified" (1) to Core (3) OR Unspecified so it counts as sleep
            let coreSamples = targetSamples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue }
            let unspecifiedSamples = targetSamples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue }
            
            let awakeSamples = targetSamples.filter { $0.value == HKCategoryValueSleepAnalysis.awake.rawValue }
            
            // Calculate unique duration for each stage
            metric.sleepDeep = calculateUniqueDuration(deepSamples)
            metric.sleepREM = calculateUniqueDuration(remSamples)
            metric.sleepCore = calculateUniqueDuration(coreSamples)
            metric.sleepUnspecified = calculateUniqueDuration(unspecifiedSamples)
            metric.sleepAwake = calculateUniqueDuration(awakeSamples)
            
            // COMPILER FIX: Break up the expression
            let deep = metric.sleepDeep ?? 0
            let core = metric.sleepCore ?? 0
            let rem = metric.sleepREM ?? 0
            let unspecified = metric.sleepUnspecified ?? 0
            let totalSleep = deep + core + rem + unspecified
            
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
    
    /// Helper to check if a source has valid sleep data (ignoring InBed/Awake)
    private func calculateTotalSleepDuration(_ samples: [SleepAnalysisSample]) -> TimeInterval {
        let validSamples = samples.filter {
            $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
            $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
            $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
            $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        }
        return calculateUniqueDuration(validSamples)
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
