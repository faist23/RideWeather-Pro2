//
//  HealthKitManager.swift
//  RideWeather Pro
//
//  Updated with wellness data fetching
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
    
    // MARK: - Read Types (Updated with Wellness)
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            // Existing readiness types
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            
            // WORKOUT ESSENTIALS
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!, 
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .cyclingPower)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!
        ]
        
        // NEW: Wellness types
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergy)
        }
        if let basalEnergy = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned) {
            types.insert(basalEnergy)
        }
        if let standHour = HKObjectType.categoryType(forIdentifier: .appleStandHour) {
            types.insert(standHour)
        }
        if let exerciseTime = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
            types.insert(exerciseTime)
        }
        if let bodyFat = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) {
            types.insert(bodyFat)
        }
        if let leanMass = HKObjectType.quantityType(forIdentifier: .leanBodyMass) {
            types.insert(leanMass)
        }
        if let respRate = HKObjectType.quantityType(forIdentifier: .respiratoryRate) {
            types.insert(respRate)
        }
        if let o2Sat = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) {
            types.insert(o2Sat)
        }
        
        return types
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
            await MainActor.run {
                self.isAuthorized = true
            }
            print("HealthKit: Authorization granted.")
            await fetchReadinessData()
            return true
        } catch {
            print("HealthKit authorization request failed: \(error.localizedDescription)")
            await MainActor.run {
                self.isAuthorized = false
            }
            return false
        }
    }
    
    // MARK: - Existing Readiness Data Fetching
    
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
        async let avgSleep = fetchAverageSleep(days: 7)
        
        let (hrv, hrvAvg, rhr, rhrAvg, sleepData, avgSleepData) = await (todaysHRV, averageHRV, todaysRHR, averageRHR, sleep, avgSleep)
        
        await MainActor.run {
            self.readiness = PhysiologicalReadiness(
                latestHRV: hrv,
                averageHRV: hrvAvg,
                latestRHR: rhr,
                averageRHR: rhrAvg,
                sleepDuration: sleepData,
                averageSleepDuration: avgSleepData
            )
            
            let sleepAvg = self.readiness.averageSleepDuration ?? 0
            print("  Sleep: \(Int((self.readiness.sleepDuration ?? 0) / 3600))h \(Int(((self.readiness.sleepDuration ?? 0).truncatingRemainder(dividingBy: 3600)) / 60))m (Avg: \(Int(sleepAvg / 3600))h \(Int((sleepAvg.truncatingRemainder(dividingBy: 3600)) / 60))m)")
        }
    }
    
    // MARK: - Weight Fetching
    
    func fetchLatestWeight() async -> Double? {
        guard isAuthorized,
              let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { (_, samples, error) in
                if let error = error {
                    print("HealthKit: Error fetching weight: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let sample = samples?.first as? HKQuantitySample else {
                    print("HealthKit: No weight data found.")
                    continuation.resume(returning: nil)
                    return
                }
                
                let weightInKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                print("HealthKit: Fetched weight: \(weightInKg) kg")
                continuation.resume(returning: weightInKg)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - NEW: Wellness Metrics Fetching
    
    /// Fetches complete wellness metrics for a specific date
    func fetchWellnessMetrics(for date: Date) async -> DailyWellnessMetrics {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        
        async let steps = fetchDailySum(for: .stepCount, date: date, unit: .count())
        async let activeEnergy = fetchDailySum(for: .activeEnergyBurned, date: date, unit: .kilocalorie())
        async let basalEnergy = fetchDailySum(for: .basalEnergyBurned, date: date, unit: .kilocalorie())
        async let standHours = fetchStandHours(for: date)
        async let exerciseMinutes = fetchDailySum(for: .appleExerciseTime, date: date, unit: .minute())
        async let sleepStages = fetchSleepStages(for: date)
        async let bodyMass = fetchLatestValue(for: .bodyMass, date: date, unit: .gramUnit(with: .kilo))
        async let bodyFat = fetchLatestValue(for: .bodyFatPercentage, date: date, unit: .percent())
        async let leanMass = fetchLatestValue(for: .leanBodyMass, date: date, unit: .gramUnit(with: .kilo))
        async let respRate = fetchDailyAverage(for: .respiratoryRate, date: date, unit: .count().unitDivided(by: .minute()))
        async let o2Sat = fetchDailyAverage(for: .oxygenSaturation, date: date, unit: .percent())
        
        let (stepsVal, activeEnergyVal, basalEnergyVal, standHoursVal, exerciseMinutesVal,
             sleepStagesVal, bodyMassVal, bodyFatVal, leanMassVal, respRateVal, o2SatVal) =
            await (steps, activeEnergy, basalEnergy, standHours, exerciseMinutes,
                   sleepStages, bodyMass, bodyFat, leanMass, respRate, o2Sat)
        
        return DailyWellnessMetrics(
            date: dayStart,
            steps: stepsVal.map { Int($0) },
            activeEnergyBurned: activeEnergyVal,
            basalEnergyBurned: basalEnergyVal,
            standHours: standHoursVal,
            exerciseMinutes: exerciseMinutesVal.map { Int($0) },
            sleepDeep: sleepStagesVal.deep,
            sleepREM: sleepStagesVal.rem,
            sleepCore: sleepStagesVal.core,
            sleepAwake: sleepStagesVal.awake,
            bodyMass: bodyMassVal,
            bodyFatPercentage: bodyFatVal,
            leanBodyMass: leanMassVal,
            respiratoryRate: respRateVal,
            oxygenSaturation: o2SatVal
        )
    }
    
    /// Fetches wellness metrics for multiple days
    func fetchWellnessMetrics(startDate: Date, endDate: Date) async -> [DailyWellnessMetrics] {
        let calendar = Calendar.current
        var metrics: [DailyWellnessMetrics] = []
        
        var currentDate = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        
        while currentDate <= end {
            let dayMetrics = await fetchWellnessMetrics(for: currentDate)
            metrics.append(dayMetrics)
            
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDay
        }
        
        return metrics
    }
    
    // MARK: - Private Helper Methods
    
    private func fetchTodaysAverage(for typeIdentifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let calendar = Calendar.current
            let startDate = calendar.startOfDay(for: Date())
            let endDate = Date()
            
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { (query, stats, error) in
                if let error = error {
                    print("HealthKit: Failed to fetch today's average for \(typeIdentifier.rawValue): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let stats = stats, let avgQuantity = stats.averageQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: avgQuantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
    
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
    
    /// etches total "asleep" time from last night with Source Prioritization
    private func fetchLastNightSleep() async -> TimeInterval? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Define "Last Night" window (Noon yesterday to Noon today)
        let cutoffHour = 6
        let currentHour = calendar.component(.hour, from: now)
        let daysBack = currentHour < cutoffHour ? 2 : 1
        
        let endNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
        let startNoon = calendar.date(byAdding: .day, value: -daysBack, to: endNoon)!
        let queryEndNoon = calendar.date(byAdding: .day, value: -(daysBack - 1), to: endNoon)!
        
        // Fetch ALL sleep samples (Stages + Unspecified)
        let predicate = HKQuery.predicateForSamples(withStart: startNoon, end: queryEndNoon, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { (query, samples, error) in
                
                guard let sleepSamples = samples as? [HKCategorySample], error == nil else {
                    continuation.resume(returning: 0)
                    return
                }
                
                // Use helper to calculate duration with source priority
                let duration = self.calculateEffectiveSleepDuration(samples: sleepSamples)
                continuation.resume(returning: duration > 0 ? duration : nil)
            }
            healthStore.execute(query)
        }
    }
    
    private func getSleepStagesDuration() async -> TimeInterval {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return 0 }
        
        let calendar = Calendar.current
        let now = Date()
        let cutoffHour = 6
        let currentHour = calendar.component(.hour, from: now)
        let daysBack = currentHour < cutoffHour ? 2 : 1
        
        let endNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
        let startNoon = calendar.date(byAdding: .day, value: -daysBack, to: endNoon)!
        let queryEndNoon = calendar.date(byAdding: .day, value: -(daysBack - 1), to: endNoon)!
        
        let startDate = startNoon
        let endDate = queryEndNoon
        
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
    
    private func getAsleepUnspecifiedDuration() async -> TimeInterval? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        let todayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
        let yesterdayNoon = calendar.date(byAdding: .day, value: -1, to: todayNoon)!
        
        let predicate = HKQuery.predicateForCategorySamples(with: .equalTo, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue)
        let timePredicate = HKQuery.predicateForSamples(withStart: yesterdayNoon, end: todayNoon, options: .strictStartDate)
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
    
    /// **FIXED:** Calculates 7-day sleep average with Source Prioritization
    private func fetchAverageSleep(days: Int) async -> TimeInterval? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return nil }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        let samples = await queryHealthKit(sampleType: sleepType, predicate: predicate)
        
        // Group by "Sleep Night" (Shift -6 hours so 11PM and 1AM land in same bucket)
        let samplesByNight = Dictionary(grouping: samples) { sample in
            let adjustedDate = sample.startDate.addingTimeInterval(-6 * 3600)
            return calendar.startOfDay(for: adjustedDate)
        }
        
        var totalDuration: TimeInterval = 0
        var validNights = 0
        
        for (_, nightSamples) in samplesByNight {
            let nightlyDuration = calculateEffectiveSleepDuration(samples: nightSamples)
            if nightlyDuration > 0 {
                totalDuration += nightlyDuration
                validNights += 1
            }
        }
        
        return validNights > 0 ? totalDuration / Double(validNights) : nil
    }
    
    private func getAverageSleepStagesDuration(days: Int) async -> TimeInterval {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return 0 }
        
        let calendar = Calendar.current
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
        return totalSleep / Double(days)
    }
    
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
    
    // MARK: - NEW: Wellness-Specific Helpers
    
    /// Fetches total sum for a quantity type on a specific day
    private func fetchDailySum(
        for typeIdentifier: HKQuantityTypeIdentifier,
        date: Date,
        unit: HKUnit
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else {
            return nil
        }
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: date)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else {
            return nil
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error = error {
                    print("HealthKit: Error fetching \(typeIdentifier.rawValue): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let stats = stats, let sum = stats.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: sum.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
    
    /// Fetches average value for a quantity type on a specific day
    private func fetchDailyAverage(
        for typeIdentifier: HKQuantityTypeIdentifier,
        date: Date,
        unit: HKUnit
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else {
            return nil
        }
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: date)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else {
            return nil
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, error in
                if let error = error {
                    print("HealthKit: Error fetching \(typeIdentifier.rawValue): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let stats = stats, let avg = stats.averageQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: avg.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
    
    /// Fetches the latest value for a quantity type on a specific day
    private func fetchLatestValue(
        for typeIdentifier: HKQuantityTypeIdentifier,
        date: Date,
        unit: HKUnit
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: typeIdentifier) else {
            return nil
        }
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: date)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else {
            return nil
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    print("HealthKit: Error fetching \(typeIdentifier.rawValue): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
    
    /// Fetches stand hours for a specific day
    private func fetchStandHours(for date: Date) async -> Int? {
        guard let standHourType = HKObjectType.categoryType(forIdentifier: .appleStandHour) else {
            return nil
        }
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: date)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else {
            return nil
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: standHourType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    print("HealthKit: Error fetching stand hours: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let standHours = samples.filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }.count
                continuation.resume(returning: standHours)
            }
            healthStore.execute(query)
        }
    }
    
    /// **NEW HELPER:** Filters sources and stages to prevent double-counting
    private func calculateEffectiveSleepDuration(samples: [HKCategorySample]) -> TimeInterval {
        // 1. Identify if AutoSleep is present
        let hasAutoSleep = samples.contains { $0.sourceRevision.source.bundleIdentifier.lowercased().contains("autosleep") }
        
        let targetSamples: [HKCategorySample]
        
        if hasAutoSleep {
            // ✅ AutoSleep Mode: Use ONLY AutoSleep samples
            targetSamples = samples.filter { $0.sourceRevision.source.bundleIdentifier.lowercased().contains("autosleep") }
        } else {
            // ⌚️ Apple Watch Mode: Use everything else
            targetSamples = samples
        }
        
        // 2. Filter Valid Stages
        // We accept Stages (Core/Deep/REM) AND "Unspecified" (AutoSleep uses this for 'Asleep')
        // We explicitly IGNORE "InBed" (value 0) or "Awake" (value 2)
        let validSamples = targetSamples.filter { sample in
            let val = sample.value
            return val == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
            val == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
            val == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
            val == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        }
        
        // 3. Calculate Duration (Deduplicated)
        return calculateUniqueDuration(validSamples)
    }
    
    /// Merges overlapping intervals
    private func calculateUniqueDuration(_ samples: [HKCategorySample]) -> TimeInterval {
        guard !samples.isEmpty else { return 0 }
        
        let sorted = samples.sorted { $0.startDate < $1.startDate }
        var totalDuration: TimeInterval = 0
        var currentStart = sorted[0].startDate
        var currentEnd = sorted[0].endDate
        
        for i in 1..<sorted.count {
            let next = sorted[i]
            if next.startDate < currentEnd {
                if next.endDate > currentEnd {
                    currentEnd = next.endDate
                }
            } else {
                totalDuration += currentEnd.timeIntervalSince(currentStart)
                currentStart = next.startDate
                currentEnd = next.endDate
            }
        }
        totalDuration += currentEnd.timeIntervalSince(currentStart)
        return totalDuration
    }
    
    /// Fetches sleep stages for the night before the given date
    private func fetchSleepStages(for date: Date) async -> (deep: TimeInterval?, rem: TimeInterval?, core: TimeInterval?, awake: TimeInterval?) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return (nil, nil, nil, nil)
        }
        
        let calendar = Calendar.current
        let todayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
        let yesterdayNoon = calendar.date(byAdding: .day, value: -1, to: todayNoon)!
        
        let predicate = HKQuery.predicateForSamples(withStart: yesterdayNoon, end: todayNoon, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    print("HealthKit: Error fetching sleep stages: \(error.localizedDescription)")
                    continuation.resume(returning: (nil, nil, nil, nil))
                    return
                }
                
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: (nil, nil, nil, nil))
                    return
                }
                
                var deep: TimeInterval = 0
                var rem: TimeInterval = 0
                var core: TimeInterval = 0
                var awake: TimeInterval = 0
                
                for sample in samples {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        deep += duration
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        rem += duration
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        core += duration
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        awake += duration
                    default:
                        break
                    }
                }
                
                continuation.resume(returning: (
                    deep > 0 ? deep : nil,
                    rem > 0 ? rem : nil,
                    core > 0 ? core : nil,
                    awake > 0 ? awake : nil
                ))
            }
            healthStore.execute(query)
        }
    }
}
/*
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
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)! //
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
            
            //            print("HealthKit Data Updated:")
            //            print("  HRV: \(self.readiness.latestHRV ?? -1)ms (Avg: \(self.readiness.averageHRV ?? -1)ms)")
            //            print("  RHR: \(self.readiness.latestRHR ?? -1)bpm (Avg: \(self.readiness.averageRHR ?? -1)bpm)")
            let sleepAvg = self.readiness.averageSleepDuration ?? 0
            print("  Sleep: \(Int((self.readiness.sleepDuration ?? 0) / 3600))h \(Int(((self.readiness.sleepDuration ?? 0).truncatingRemainder(dividingBy: 3600)) / 60))m (Avg: \(Int(sleepAvg / 3600))h \(Int((sleepAvg.truncatingRemainder(dividingBy: 3600)) / 60))m)")
        }
    }
    
    // MARK: - NEW: Weight Fetching
    
    /// Fetches the most recent weight entry from HealthKit in Kilograms
    func fetchLatestWeight() async -> Double? {
        guard isAuthorized,
              let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            // Sort by date descending to get the newest
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { (_, samples, error) in
                if let error = error {
                    print("HealthKit: Error fetching weight: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let sample = samples?.first as? HKQuantitySample else {
                    print("HealthKit: No weight data found.")
                    continuation.resume(returning: nil)
                    return
                }
                
                // Convert to kg
                let weightInKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                print("HealthKit: Fetched weight: \(weightInKg) kg")
                continuation.resume(returning: weightInKg)
            }
            
            healthStore.execute(query)
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
    
    /// **FIXED:** Fetches total "asleep" time from last night by summing stages, with a fallback.
    private func fetchLastNightSleep() async -> TimeInterval? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        
        // 1. Try to get the sum of sleep stages first
        let stageSum = await getSleepStagesDuration()
        
        if stageSum > 0 {
            return stageSum
        }
        
        // 2. Fallback: If no stages, find "asleepUnspecified"
        print("HealthKit: No sleep stages found. Falling back to 'asleepUnspecified'.")
        return await getAsleepUnspecifiedDuration()
    }
    
    /// Helper to get the sum of Core, Deep, and REM sleep from LAST NIGHT.
    private func getSleepStagesDuration() async -> TimeInterval {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return 0 }
        
        let calendar = Calendar.current
        
        // Get a wider window: from 12 PM yesterday through 2 PM today
        // This captures any sleep session that occurred "last night"
        let now = Date()
        
        // If it's before 6 AM, we want yesterday's sleep
        // If it's after 6 AM, we want last night's sleep (which may have ended this morning)
        let cutoffHour = 6
        let currentHour = calendar.component(.hour, from: now)
        
        let daysBack = currentHour < cutoffHour ? 2 : 1
        
        // Query from noon X days ago to noon X-1 days ago
        let endNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
        let startNoon = calendar.date(byAdding: .day, value: -daysBack, to: endNoon)!
        let queryEndNoon = calendar.date(byAdding: .day, value: -(daysBack - 1), to: endNoon)!
        
        let startDate = startNoon
        let endDate = queryEndNoon
        
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
                
                // Debug: Print what we found
                print("HealthKit: Found \(sleepSamples.count) sleep stage samples")
                for sample in sleepSamples.prefix(5) {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate) / 3600
                    print("  Sample: \(sample.startDate) to \(sample.endDate) (\(String(format: "%.2f", duration))h)")
                }
                
                let totalSleep = sleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                print("HealthKit: Total sleep from stages: \(String(format: "%.2f", totalSleep / 3600))h")
                continuation.resume(returning: totalSleep)
            }
            healthStore.execute(query)
        }
    }
    
    /// Helper to get the sum of "asleepUnspecified" from LAST NIGHT (for devices that don't provide stages).
    private func getAsleepUnspecifiedDuration() async -> TimeInterval? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        let todayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
        let yesterdayNoon = calendar.date(byAdding: .day, value: -1, to: todayNoon)!
        
        let predicate = HKQuery.predicateForCategorySamples(with: .equalTo, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue)
        let timePredicate = HKQuery.predicateForSamples(withStart: yesterdayNoon, end: todayNoon, options: .strictStartDate)
        let combinedPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, timePredicate])
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: combinedPredicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { (query, samples, error) in
                
                guard let sleepSamples = samples as? [HKCategorySample], error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                
                print("HealthKit: Found \(sleepSamples.count) asleepUnspecified samples")
                
                let totalSleep = sleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                print("HealthKit: Total sleep from asleepUnspecified: \(String(format: "%.2f", totalSleep / 3600))h")
                continuation.resume(returning: totalSleep > 0 ? totalSleep : nil)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchAverageSleep(days: Int) async -> TimeInterval? {
        // First, try to get the average of stages
        let stageAvg = await getAverageSleepStagesDuration(days: days)
        if stageAvg > 0 {
            //            print("HealthKit: Found 7-day avg for sleep stages.")
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
*/
