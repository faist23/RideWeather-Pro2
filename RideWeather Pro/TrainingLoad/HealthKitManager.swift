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
        
        // Wellness types
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
    
    // MARK: - Disconnect
    
    func disconnect() {
        // We cannot programmatically revoke iOS permissions, but we can reset our app's state.
        // This stops the app from fetching data until the next launch or reconnect.
        isAuthorized = false
        readiness = PhysiologicalReadiness() // Clear data
        print("HealthKit: Disconnected by user.")
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
        // Standard fetches
        async let steps = fetchDailySum(for: .stepCount, date: date, unit: .count())
        async let activeEnergy = fetchDailySum(for: .activeEnergyBurned, date: date, unit: .kilocalorie())
        async let basalEnergy = fetchDailySum(for: .basalEnergyBurned, date: date, unit: .kilocalorie())
        async let standHours = fetchStandHours(for: date)
        async let exerciseMinutes = fetchDailySum(for: .appleExerciseTime, date: date, unit: .minute())
        
        // Debug Sleep Stages
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
            date: Calendar.current.startOfDay(for: date),
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
    
    private func fetchLastNightSleep() async -> TimeInterval? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Look back 24h from noon to ensure we cover the full night
        let endNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
        let startNoon = calendar.date(byAdding: .day, value: -1, to: endNoon)!
        
        let predicate = HKQuery.predicateForSamples(withStart: startNoon, end: endNoon, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [weak self] (query, samples, error) in
                
                guard let sleepSamples = samples as? [HKCategorySample], error == nil else {
                    continuation.resume(returning: 0)
                    return
                }
                
                // Uses the new SMART logic defined above
                let duration = self?.calculateEffectiveSleepDuration(samples: sleepSamples) ?? 0
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
    
    /// Calculates 7-day sleep average with Source Prioritization
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
    
    // MARK: - Smart Sleep Filtering
        
        /// Filters sources to prevent double-counting, but falls back to Apple Watch if AutoSleep is empty
        private func calculateEffectiveSleepDuration(samples: [HKCategorySample]) -> TimeInterval {
            // 1. Identify AutoSleep Data
            let autoSleepSamples = samples.filter { $0.sourceRevision.source.bundleIdentifier.lowercased().contains("autosleep") }
            let hasAutoSleep = !autoSleepSamples.isEmpty
            
            var targetSamples: [HKCategorySample] = []
            
            if hasAutoSleep {
                // CHECK: Does AutoSleep actually have "Asleep" data? (Value 1, 3, 4, or 5)
                // If it only has "InBed" (Value 0), this will be false.
                let hasValidSleepData = autoSleepSamples.contains { sample in
                    let val = sample.value
                    return val == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                           val == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                           val == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                           val == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                }
                
                if hasValidSleepData {
                    // Case A: AutoSleep is good. Use it (and ignore Apple Watch to prevent duplicates).
                    targetSamples = autoSleepSamples
                } else {
                    // Case B (Your 12/27 Issue): AutoSleep exists but has 0 sleep.
                    // FALLBACK: Use everything ELSE (Apple Watch).
                    print("   ⚠️ AutoSleep detected but empty. Falling back to Apple Watch.")
                    targetSamples = samples.filter { !$0.sourceRevision.source.bundleIdentifier.lowercased().contains("autosleep") }
                }
            } else {
                // Case C: No AutoSleep at all. Use standard Apple Watch data.
                targetSamples = samples
            }
            
            // 2. Filter for Sleep Stages (exclude InBed/Awake)
            let validSamples = targetSamples.filter { sample in
                let val = sample.value
                return val == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                       val == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                       val == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                       val == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
            }
            
            return calculateUniqueDuration(validSamples)
        }

        /// Updates stage fetching to use the same fallback logic
    private func fetchSleepStages(for date: Date) async -> (deep: TimeInterval?, rem: TimeInterval?, core: TimeInterval?, awake: TimeInterval?, unspecified: TimeInterval?) {
            guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return (nil, nil, nil, nil, nil) }
            
            let calendar = Calendar.current
            let todayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
            let yesterdayNoon = calendar.date(byAdding: .day, value: -1, to: todayNoon)!
            
            let predicate = HKQuery.predicateForSamples(withStart: yesterdayNoon, end: todayNoon, options: .strictStartDate)
            
            return await withCheckedContinuation { continuation in
                let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                    
                    guard let samples = samples as? [HKCategorySample], error == nil else {
                        continuation.resume(returning: (nil, nil, nil, nil, nil))
                        return
                    }
                    
                    // --- STRATEGY: CALCULATE BOTH, PICK WINNER ---
                    
                    // 1. Calculate AutoSleep Totals
                    let autoSleepSamples = samples.filter { $0.sourceRevision.source.bundleIdentifier.lowercased().contains("autosleep") }
                    let autoSleepMetrics = self.calculateMetrics(for: autoSleepSamples)
                    let autoSleepTotal = (autoSleepMetrics.deep ?? 0) + (autoSleepMetrics.rem ?? 0) + (autoSleepMetrics.core ?? 0) + (autoSleepMetrics.unspecified ?? 0)
                    
                    // 2. Calculate Apple Watch (Other) Totals
                    let otherSamples = samples.filter { !$0.sourceRevision.source.bundleIdentifier.lowercased().contains("autosleep") }
                    let otherMetrics = self.calculateMetrics(for: otherSamples)
                    let otherTotal = (otherMetrics.deep ?? 0) + (otherMetrics.rem ?? 0) + (otherMetrics.core ?? 0) + (otherMetrics.unspecified ?? 0)
                    
                    // 3. Decision Logic
                    print("💤 Sleep Check for \(date.formatted(date: .numeric, time: .omitted)):")
                    print("   🔹 AutoSleep Found: \(autoSleepTotal/3600.0)h")
                    print("   🔹 AppleWatch Found: \(otherTotal/3600.0)h")
                    
                    if autoSleepTotal > 0 {
                        print("   ✅ DECISION: Using AutoSleep")
                        continuation.resume(returning: autoSleepMetrics)
                    } else if otherTotal > 0 {
                        print("   ⚠️ DECISION: AutoSleep was 0h. Falling back to Apple Watch.")
                        continuation.resume(returning: otherMetrics)
                    } else {
                        print("   ❌ DECISION: No sleep data found from any source.")
                        continuation.resume(returning: (nil, nil, nil, nil, nil))
                    }
                }
                healthStore.execute(query)
            }
        }
        
        /// Helper to sum up stages for a set of samples
        private func calculateMetrics(for samples: [HKCategorySample]) -> (deep: TimeInterval?, rem: TimeInterval?, core: TimeInterval?, awake: TimeInterval?, unspecified: TimeInterval?) {
            var deep: TimeInterval = 0
            var rem: TimeInterval = 0
            var core: TimeInterval = 0
            var awake: TimeInterval = 0
            var unspecified: TimeInterval = 0
            
            for sample in samples {
                let duration = sample.endDate.timeIntervalSince(sample.startDate)
                switch sample.value {
                case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: deep += duration
                case HKCategoryValueSleepAnalysis.asleepREM.rawValue: rem += duration
                case HKCategoryValueSleepAnalysis.asleepCore.rawValue: core += duration
                case HKCategoryValueSleepAnalysis.awake.rawValue: awake += duration
                case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: unspecified += duration
                default: break
                }
            }
            
            return (
                deep > 0 ? deep : nil,
                rem > 0 ? rem : nil,
                core > 0 ? core : nil,
                awake > 0 ? awake : nil,
                unspecified > 0 ? unspecified : nil
            )
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

}
