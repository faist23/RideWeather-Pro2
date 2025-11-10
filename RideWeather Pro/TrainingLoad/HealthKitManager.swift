//
//  HealthKitManager.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 11/9/25.
//

import Foundation
import HealthKit
import Combine

@MainActor
class HealthKitManager: ObservableObject {
    
    let healthStore = HKHealthStore()
    
    // MARK: - Published Properties
    @Published var isAuthorized: Bool = false
    @Published var readiness = PhysiologicalReadiness()
    
    // Define the data types we want to read
    private var readTypes: Set<HKObjectType> {
        return [
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
    }
    
    init() {
        checkAuthorization()
    }
    
    // MARK: - Authorization
    
    func checkAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit: Not available on this device.")
            self.isAuthorized = false
            return
        }
        
        healthStore.getRequestStatusForAuthorization(toShare: [], read: readTypes) { [weak self] (status, error) in
            DispatchQueue.main.async {
                guard error == nil else {
                    print("HealthKit Auth Check Error: \(error!.localizedDescription)")
                    self?.isAuthorized = false
                    return
                }
                
                self?.isAuthorized = (status == .unnecessary)
                if self?.isAuthorized == true {
                    print("HealthKit: Authorization previously granted.")
                    // Fetch data on launch if already authorized
                    Task {
                        await self?.fetchReadinessData()
                    }
                } else {
                    print("HealthKit: Authorization not yet granted.")
                }
            }
        }
    }
    
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit: Not available on this device.")
            return false
        }
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            // After request, update status
            await MainActor.run {
                self.isAuthorized = true
            }
            print("HealthKit: Authorization granted.")
            await fetchReadinessData() // Fetch data immediately after permission
            return true
        } catch {
            print("HealthKit authorization request failed: \(error.localizedDescription)")
            await MainActor.run {
                self.isAuthorized = false
            }
            return false
        }
    }
    
    // MARK: - Data Fetching
    
    func fetchReadinessData() async {
        guard isAuthorized else {
            print("HealthKit: Not authorized. Skipping data fetch.")
            return
        }
        
        print("HealthKit: Fetching readiness data...")
        
        async let todaysHRV = fetchTodaysAverage(for: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let averageHRV = fetchAverage(for: .heartRateVariabilitySDNN, days: 7, unit: .secondUnit(with: .milli))
        async let todaysRHR = fetchTodaysAverage(for: .restingHeartRate, unit: .count().unitDivided(by: .minute()))
        async let averageRHR = fetchAverage(for: .restingHeartRate, days: 7, unit: .count().unitDivided(by: .minute()))
        async let sleep = fetchLastNightSleep()
        async let avgSleep = fetchAverageSleep(days: 7) // <-- ADD THIS
        
        // Await all results
        let (hrv, hrvAvg, rhr, rhrAvg, sleepData, avgSleepData) = await (todaysHRV, averageHRV, todaysRHR, averageRHR, sleep, avgSleep) // <-- ADD THIS
        
        // Update the published readiness struct on the main thread
        await MainActor.run {
            self.readiness = PhysiologicalReadiness(
                latestHRV: hrv, // HRV in ms
                averageHRV: hrvAvg,
                latestRHR: rhr, // RHR in bpm
                averageRHR: rhrAvg,
                sleepDuration: sleepData,
                averageSleepDuration: avgSleepData // <-- ADD THIS
            )
            
            print("HealthKit Data Updated:")
            print("  HRV: \(self.readiness.latestHRV ?? -1)ms (Avg: \(self.readiness.averageHRV ?? -1)ms)")
            print("  RHR: \(self.readiness.latestRHR ?? -1)bpm (Avg: \(self.readiness.averageRHR ?? -1)bpm)")
            let sleepAvg = self.readiness.averageSleepDuration ?? 0
            print("  Sleep: \(Int((self.readiness.sleepDuration ?? 0) / 3600))h \(Int(((self.readiness.sleepDuration ?? 0).truncatingRemainder(dividingBy: 3600)) / 60))m (Avg: \(Int(sleepAvg / 3600))h \(Int((sleepAvg.truncatingRemainder(dividingBy: 3600)) / 60))m)")
        }
    }
    
    /// **WORKING:** Fetches the *average* of all samples recorded *today*.
    private func fetchTodaysAverage(for typeIdentifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let calendar = Calendar.current
            let startDate = calendar.startOfDay(for: Date()) // 12:00 AM today
            let endDate = Date() // Now
            
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage // Get the average of all samples in this window
            ) { (query, stats, error) in
                if let error = error {
                    print("HealthKit: Failed to fetch today's average for \(typeIdentifier.rawValue): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let stats = stats, let avgQuantity = stats.averageQuantity() else {
                    continuation.resume(returning: nil) // No data for today, which is fine
                    return
                }
                
                continuation.resume(returning: avgQuantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
    
    /// **WORKING:** Fetches the average of a metric using the classic HKStatisticsQuery.
    private func fetchAverage(for typeIdentifier: HKQuantityTypeIdentifier, days: Int, unit: HKUnit) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else {
            return nil
        }
        
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return nil }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { (query, stats, error) in
                if let error = error {
                    print("HealthKit: Failed to fetch average for \(typeIdentifier.rawValue): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let stats = stats else {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: stats.averageQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
    
    /// **FIXED:** Fetches total "asleep" time by summing stages, with a fallback.
    private func fetchLastNightSleep() async -> TimeInterval? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        
        // 1. Try to get the sum of sleep stages first
        let stageSum = await getSleepStagesDuration()
        
        if stageSum > 0 {
            print("HealthKit: Found sleep stages (Core, Deep, REM). Total: \(stageSum / 3600) hrs")
            return stageSum
        }
        
        // 2. Fallback: If no stages, find "asleepUnspecified"
        print("HealthKit: No sleep stages found. Falling back to 'asleepUnspecified'.")
        return await getAsleepUnspecifiedDuration()
    }
    
    /// Helper to get the sum of Core, Deep, and REM sleep.
    private func getSleepStagesDuration() async -> TimeInterval {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return 0 }
        
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .hour, value: -18, to: endDate) else { return 0 }
        
        // 1. Find all *stage* sleep states
        let stagePredicates = [
            HKCategoryValueSleepAnalysis.asleepCore,
            HKCategoryValueSleepAnalysis.asleepDeep,
            HKCategoryValueSleepAnalysis.asleepREM
        ].map {
            HKQuery.predicateForCategorySamples(with: .equalTo, value: $0.rawValue)
        }
        
        let sleepOrPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: stagePredicates)
        let timePredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let combinedPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [sleepOrPredicate, timePredicate])
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: combinedPredicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { (query, samples, error) in
                
                guard let sleepSamples = samples as? [HKCategorySample], error == nil else {
                    continuation.resume(returning: 0)
                    return
                }
                
                let totalSleep = sleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: totalSleep)
            }
            healthStore.execute(query)
        }
    }
    
    /// Helper to get the sum of "asleepUnspecified" (for devices that don't provide stages).
    private func getAsleepUnspecifiedDuration() async -> TimeInterval? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .hour, value: -18, to: endDate) else { return nil }
        
        let predicate = HKQuery.predicateForCategorySamples(with: .equalTo, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue)
        let timePredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let combinedPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, timePredicate])
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: combinedPredicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { (query, samples, error) in
                
                guard let sleepSamples = samples as? [HKCategorySample], error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let totalSleep = sleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: totalSleep > 0 ? totalSleep : nil)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchAverageSleep(days: Int) async -> TimeInterval? {
        // First, try to get the average of stages
        let stageAvg = await getAverageSleepStagesDuration(days: days)
        if stageAvg > 0 {
            print("HealthKit: Found 7-day avg for sleep stages.")
            return stageAvg
        }
        
        // Fallback: If no stages, get average of "asleepUnspecified"
        print("HealthKit: No 7-day avg for sleep stages. Falling back to 'asleepUnspecified'.")
        return await getAverageAsleepUnspecifiedDuration(days: days)
    }
  
    /// Helper to get the average duration of Core, Deep, and REM sleep over N days.
    private func getAverageSleepStagesDuration(days: Int) async -> TimeInterval {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return 0 }
        
        let calendar = Calendar.current
        // We want the average from the last 7 *days*, so end date is start of today
        let endDate = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return 0 }
        
        let stagePredicates = [
            HKCategoryValueSleepAnalysis.asleepCore,
            HKCategoryValueSleepAnalysis.asleepDeep,
            HKCategoryValueSleepAnalysis.asleepREM
        ].map {
            HKQuery.predicateForCategorySamples(with: .equalTo, value: $0.rawValue)
        }
        
        let sleepOrPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: stagePredicates)
        let timePredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let combinedPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [sleepOrPredicate, timePredicate])
        
        let samples = await queryHealthKit(sampleType: sleepType, predicate: combinedPredicate)
        
        let totalSleep = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return totalSleep / Double(days) // Return the average per day
    }
    
    /// Helper to get the average "asleepUnspecified" duration over N days (fallback).
    private func getAverageAsleepUnspecifiedDuration(days: Int) async -> TimeInterval? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return nil }
        
        let predicate = HKQuery.predicateForCategorySamples(with: .equalTo, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue)
        let timePredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let combinedPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, timePredicate])
        
        let samples = await queryHealthKit(sampleType: sleepType, predicate: combinedPredicate)
        
        let totalSleep = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return totalSleep > 0 ? totalSleep / Double(days) : nil
    }
    
    private func queryHealthKit(sampleType: HKSampleType, predicate: NSPredicate) async -> [HKCategorySample] {
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { (query, samples, error) in
                if let error = error {
                    print("HealthKit: Failed to run query: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            }
            healthStore.execute(query)
        }
    }
}
