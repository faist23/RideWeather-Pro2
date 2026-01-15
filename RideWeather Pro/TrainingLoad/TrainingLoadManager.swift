//
//  TrainingLoadManager.swift
//  RideWeather Pro
//
//  Manager for calculating and persisting training load metrics
//  Uses file-based storage instead of UserDefaults
//

import Foundation

class TrainingLoadManager {
    static let shared = TrainingLoadManager()
    
    private let storage = TrainingLoadStorage.shared  // Changed from UserDefaults
    private let emaATLDays = 7
    private let emaCTLDays = 42
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Adds a new ride to training load calculations
    func addRide(analysis: RideAnalysis) {
        let calendar = Calendar.current
        let rideDate = calendar.startOfDay(for: analysis.date)
        
        var dailyLoads = loadAllDailyLoads()
        
        // Find or create daily load for this date
        if let existingIndex = dailyLoads.firstIndex(where: {
            calendar.isDate($0.date, inSameDayAs: rideDate)
        }) {
            // Add to existing day
            dailyLoads[existingIndex].tss += analysis.trainingStressScore
            dailyLoads[existingIndex].rideCount += 1
            dailyLoads[existingIndex].totalDistance += analysis.distance
            dailyLoads[existingIndex].totalDuration += analysis.duration
        } else {
            // Create new day
            let newLoad = DailyTrainingLoad(
                date: rideDate,
                tss: analysis.trainingStressScore,
                rideCount: 1,
                totalDistance: analysis.distance,
                totalDuration: analysis.duration
            )
            dailyLoads.append(newLoad)
        }
        
        // Sort by date
        dailyLoads.sort { $0.date < $1.date }
        
        // Recalculate all metrics
        let updatedLoads = recalculateMetrics(for: dailyLoads)
        
        // Save
        saveDailyLoads(updatedLoads)
        
        // Save the PRECISE timestamp of this ride
        // We only update if this ride is newer than what we have (in case of historical imports)
        let lastKnown = UserDefaults.standard.object(forKey: "last_ride_precise_date") as? Date ?? Date.distantPast
        if analysis.date > lastKnown {
            UserDefaults.standard.set(analysis.date, forKey: "last_ride_precise_date")
            print("💾 Saved precise last ride time: \(analysis.date.formatted())")
        }
        
        PhoneSessionManager.shared.sendUpdate()

        print("✅ Training Load: Added ride with \(Int(analysis.trainingStressScore)) TSS on \(rideDate)")
    }
    
    /// Gets current training load summary
    func getCurrentSummary() -> TrainingLoadSummary? {
        let loads = loadAllDailyLoads()
        guard !loads.isEmpty else { return nil }
        
        let sortedLoads = loads.sorted { $0.date > $1.date }
        guard let latest = sortedLoads.first,
              let atl = latest.atl,
              let ctl = latest.ctl,
              let tsb = latest.tsb else {
            return nil
        }
        
        // Calculate weekly TSS
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let weeklyTSS = loads.filter { $0.date >= weekAgo }
            .reduce(0.0) { $0 + $1.tss }
        
        // Calculate ramp rate (CTL change over last 7 days)
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: latest.date)!
        let previousCTL = loads.first(where: { Calendar.current.isDate($0.date, inSameDayAs: sevenDaysAgo) })?.ctl ?? ctl
        let rampRate = ctl - previousCTL
        
        let recommendation = generateRecommendation(
            atl: atl,
            ctl: ctl,
            tsb: tsb,
            rampRate: rampRate
        )
        
        return TrainingLoadSummary(
            currentATL: atl,
            currentCTL: ctl,
            currentTSB: tsb,
            weeklyTSS: weeklyTSS,
            rampRate: rampRate,
            formStatus: latest.formStatus,
            recommendation: recommendation
        )
    }
    
    /// Gets daily loads for a specific period
    func getDailyLoads(for period: TrainingLoadPeriod) -> [DailyTrainingLoad] {
        let loads = loadAllDailyLoads()
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -period.days, to: Date())!
        
        return loads.filter { $0.date >= cutoffDate }
            .sorted { $0.date > $1.date }
    }
    
    /// Gets insights based on current training load AND physiological readiness
    func getInsights(readiness: PhysiologicalReadiness? = nil) -> [TrainingLoadInsight] {
        guard let summary = getCurrentSummary() else {
            return [TrainingLoadInsight(
                priority: .info,
                title: "No Training Data",
                message: "Import rides from Strava to start tracking your training load.",
                recommendation: "Your fitness (CTL), fatigue (ATL), and form (TSB) will appear here.",
                icon: "figure.outdoor.cycle"
            )]
        }
        
        var insights: [TrainingLoadInsight] = []
        
        // --- 1. HEALTHKIT-BASED INSIGHTS ---
        if let readiness = readiness {
            
            // Check for Readiness Mismatch (High TSB, but poor metrics)
            let hrvIsLow = (readiness.latestHRV ?? 50) < ((readiness.averageHRV ?? 50) * 0.85)
            let rhrIsHigh = (readiness.latestRHR ?? 60) > ((readiness.averageRHR ?? 60) + 4)
            
            if summary.currentTSB > 5 && (hrvIsLow || rhrIsHigh) {
                var reason = ""
                if hrvIsLow, let hrv = readiness.latestHRV, let avgHRV = readiness.averageHRV {
                    reason = "HRV is \(Int(hrv))ms (well below your avg of \(Int(avgHRV))ms)."
                }
                if rhrIsHigh, let rhr = readiness.latestRHR, let avgRHR = readiness.averageRHR {
                    reason = "Resting HR is \(Int(rhr))bpm (above your avg of \(Int(avgRHR))bpm)."
                }
                
                insights.append(TrainingLoadInsight(
                    priority: .critical,
                    title: "Readiness Mismatch",
                    message: "Your Form (TSB \(Int(summary.currentTSB))) is positive, but your body shows high stress. \(reason)",
                    recommendation: "Your body is not recovered (illness, poor sleep, life stress). A high TSB is misleading. Strongly consider an easy recovery day.",
                    icon: "exclamationmark.triangle.fill"
                ))
            }
            
            // Check for "Green Light" (Good TSB, Good metrics)
            let hrvIsHigh = (readiness.latestHRV ?? 0) > (readiness.averageHRV ?? 1)
            let rhrIsNormal = (readiness.latestRHR ?? 100) < (readiness.averageRHR ?? 101)
            let goodSleep = (readiness.sleepDuration ?? 0) > (7 * 3600)
            
            if (summary.currentTSB > -15 && summary.currentTSB < 15) && (hrvIsHigh || rhrIsNormal) && goodSleep {
                insights.append(TrainingLoadInsight(
                    priority: .success,
                    title: "Primed for Performance",
                    message: "TSB is optimal and recovery metrics (HRV/RHR/Sleep) are strong.",
                    recommendation: "This is a perfect day to execute a key high-intensity workout. Your body is fit, fresh, and ready to adapt.",
                    icon: "checkmark.seal.fill"
                ))
            }
            
            // Check for "Inadequate Recovery"
            let isBuildingFatigue = summary.currentATL > (summary.currentCTL * 0.9)
            let shortSleep = (readiness.sleepDuration ?? 8*3600) < (6 * 3600)
            
            if isBuildingFatigue && shortSleep {
                insights.append(TrainingLoadInsight(
                    priority: .warning,
                    title: "Inadequate Recovery",
                    message: "Your Fatigue (ATL) is high, but you only slept \(Int((readiness.sleepDuration ?? 0) / 3600)) hours.",
                    recommendation: "You are not recovering from your training. Prioritize 7-9 hours of sleep tonight or schedule a rest day to avoid overtraining.",
                    icon: "battery.25"
                ))
            }
        }
        
        // --- 2. EXISTING TSB-BASED INSIGHTS ---
        
        if !insights.contains(where: { $0.priority == .critical }) {
            switch summary.formStatus {
            case .veryFatigued:
                insights.append(TrainingLoadInsight(
                    priority: .critical,
                    title: "High Fatigue Level",
                    message: "TSB: \(Int(summary.currentTSB)). Your body needs recovery.",
                    recommendation: "Take 2-3 easy days or rest completely. Fatigue this high increases injury risk.",
                    icon: "exclamationmark.triangle.fill"
                ))
                
            case .fatigued:
                insights.append(TrainingLoadInsight(
                    priority: .warning,
                    title: "Building Fatigue",
                    message: "TSB: \(Int(summary.currentTSB)). You're carrying significant fatigue.",
                    recommendation: "Schedule an easy day or rest day in the next 48 hours.",
                    icon: "battery.25"
                ))
                
            case .fresh, .veryFresh:
                if !insights.contains(where: { $0.priority == .success }) {
                    insights.append(TrainingLoadInsight(
                        priority: .success,
                        title: "Well Recovered",
                        message: "TSB: \(Int(summary.currentTSB)). You're fresh and ready for hard efforts.",
                        recommendation: "Good time for high-intensity training or racing.",
                        icon: "bolt.fill"
                    ))
                }
            default:
                break
            }
        }
        
        // Ramp rate insight
        if !summary.isSafeRampRate {
            if summary.rampRate > 8 {
                insights.append(TrainingLoadInsight(
                    priority: .warning,
                    title: "Building Too Fast",
                    message: "CTL increasing by \(String(format: "%.1f", summary.rampRate)) TSS/week.",
                    recommendation: "Safe rate is 5-8 TSS/week. Slow down to avoid overtraining or injury.",
                    icon: "speedometer"
                ))
            } else if summary.rampRate < -8 {
                insights.append(TrainingLoadInsight(
                    priority: .info,
                    title: "Fitness Declining",
                    message: "CTL decreasing by \(String(format: "%.1f", abs(summary.rampRate))) TSS/week.",
                    recommendation: "If intentional taper, perfect. Otherwise, increase training volume gradually.",
                    icon: "arrow.down.circle"
                ))
            }
        } else if summary.rampRate > 5 {
            insights.append(TrainingLoadInsight(
                priority: .success,
                title: "Building Fitness Safely",
                message: "CTL increasing by \(String(format: "%.1f", summary.rampRate)) TSS/week.",
                recommendation: "You're in the optimal building range. Keep this up for sustained improvement.",
                icon: "arrow.up.circle.fill"
            ))
        }
        
        // CTL vs ATL relationship
        let fitnessToFatigueRatio = summary.currentCTL / max(summary.currentATL, 1)
        if fitnessToFatigueRatio < 0.9 {
            insights.append(TrainingLoadInsight(
                priority: .warning,
                title: "Fatigue Exceeds Fitness",
                message: "Short-term load is higher than long-term fitness.",
                recommendation: "You're accumulating fatigue faster than building fitness. Consider a recovery week.",
                icon: "chart.line.downtrend.xyaxis"
            ))
        }
        
        // Weekly TSS targets
        let targetWeeklyTSS = summary.currentCTL * 0.7
        if summary.weeklyTSS < targetWeeklyTSS * 0.5 && summary.currentCTL > 10 {
            insights.append(TrainingLoadInsight(
                priority: .info,
                title: "Low Training Volume",
                message: "Weekly TSS: \(Int(summary.weeklyTSS)), Target: ~\(Int(targetWeeklyTSS))",
                recommendation: "Increase weekly volume gradually to maintain fitness.",
                icon: "arrow.up"
            ))
        }
        
        return insights.sorted {
            let priorityOrder: [TrainingLoadInsight.Priority: Int] = [
                .critical: 0, .warning: 1, .info: 2, .success: 3
            ]
            return (priorityOrder[$0.priority] ?? 4) < (priorityOrder[$1.priority] ?? 4)
        }
    }
    
    /// Deletes a ride from training load
    func deleteRide(analysisId: UUID, tss: Double, date: Date) {
        let calendar = Calendar.current
        let rideDate = calendar.startOfDay(for: date)
        
        var dailyLoads = loadAllDailyLoads()
        
        if let existingIndex = dailyLoads.firstIndex(where: {
            calendar.isDate($0.date, inSameDayAs: rideDate)
        }) {
            dailyLoads[existingIndex].tss = max(0, dailyLoads[existingIndex].tss - tss)
            dailyLoads[existingIndex].rideCount = max(0, dailyLoads[existingIndex].rideCount - 1)
            
            if dailyLoads[existingIndex].rideCount == 0 {
                dailyLoads.remove(at: existingIndex)
            }
            
            let updatedLoads = recalculateMetrics(for: dailyLoads)
            saveDailyLoads(updatedLoads)
            
            print("✅ Training Load: Removed ride with \(Int(tss)) TSS from \(rideDate)")
        }
    }
    
    /// Clears all training load data
    func clearAll() {
        storage.clearAll()  // Changed from UserDefaults
        print("🗑️ Training Load: All data cleared")
    }
    
    /// Exports training load data to CSV
    func exportToCSV() -> String {
        let loads = loadAllDailyLoads()
        var csv = "Date,TSS,ATL,CTL,TSB,Rides,Distance(km),Duration(min)\n"
        
        for load in loads.sorted(by: { $0.date < $1.date }) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateStr = dateFormatter.string(from: load.date)
            
            let atl = load.atl.map { String(format: "%.1f", $0) } ?? ""
            let ctl = load.ctl.map { String(format: "%.1f", $0) } ?? ""
            let tsb = load.tsb.map { String(format: "%.1f", $0) } ?? ""
            let distance = String(format: "%.1f", load.totalDistance / 1000)
            let duration = String(format: "%.0f", load.totalDuration / 60)
            
            csv += "\(dateStr),\(Int(load.tss)),\(atl),\(ctl),\(tsb),\(load.rideCount),\(distance),\(duration)\n"
        }
        
        return csv
    }
    
    /// Returns the current storage size with day count
    func getStorageInfo() -> String {
        let count = loadAllDailyLoads().count
        let size = storage.getStorageSizeFormatted()
        return "\(count) days (\(size))"
    }
    
    // MARK: - Private Methods
    
    func loadAllDailyLoads() -> [DailyTrainingLoad] {
        return storage.loadAllDailyLoads()  // Changed from UserDefaults
    }
    
    func saveDailyLoads(_ loads: [DailyTrainingLoad]) {
        storage.saveDailyLoads(loads)  // Changed from UserDefaults
    }
    
    func recalculateMetrics(for loads: [DailyTrainingLoad]) -> [DailyTrainingLoad] {
        var updatedLoads = loads.sorted { $0.date < $1.date }
        var previousATL: Double = 0
        var previousCTL: Double = 0
        
        for i in 0..<updatedLoads.count {
            let todayTSS = updatedLoads[i].tss
            
            let atl = calculateEMA(
                previousValue: previousATL,
                newValue: todayTSS,
                days: emaATLDays
            )
            
            let ctl = calculateEMA(
                previousValue: previousCTL,
                newValue: todayTSS,
                days: emaCTLDays
            )
            
            let tsb = ctl - atl
            
            updatedLoads[i].atl = atl
            updatedLoads[i].ctl = ctl
            updatedLoads[i].tsb = tsb
            
            previousATL = atl
            previousCTL = ctl
        }
        
        return updatedLoads
    }
    
    private func calculateEMA(previousValue: Double, newValue: Double, days: Int) -> Double {
        let alpha = 2.0 / Double(days + 1)
        return previousValue + alpha * (newValue - previousValue)
    }
    
    private func generateRecommendation(atl: Double, ctl: Double, tsb: Double, rampRate: Double) -> String {
        if tsb < -30 {
            return "Take 2-3 rest days. Your fatigue is very high and needs immediate recovery."
        }
        
        if tsb < -10 {
            return "Schedule an easy day or rest day soon. You're building significant fatigue."
        }
        
        if tsb > 15 {
            if rampRate < -5 {
                return "You're fresh but detraining. Consider increasing training volume gradually."
            }
            return "Perfect time for a hard workout or race. You're well-recovered and ready."
        }
        
        if tsb > 5 {
            return "Good recovery status. You can handle high-intensity training today."
        }
        
        if rampRate > 8 {
            return "Slow down your build. Increase training load by no more than 5-8 TSS/week."
        }
        
        if rampRate > 3 && rampRate <= 8 {
            return "Excellent! You're building fitness at a sustainable rate."
        }
        
        if abs(rampRate) <= 3 {
            return "Maintaining current fitness level. Increase volume gradually if you want to improve."
        }
        
        return "Continue with balanced training. Mix hard and easy days appropriately."
    }
    
    /// Ensures we have data for every day (fills gaps with zero TSS)
    func fillMissingDays() {
        var loads = loadAllDailyLoads()
        guard !loads.isEmpty else { return }
        
        let sortedLoads = loads.sorted { $0.date < $1.date }
        guard let firstDate = sortedLoads.first?.date else { return }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        var currentDate = firstDate
        var filledLoads: [DailyTrainingLoad] = []
        
        while currentDate <= today {
            if let existing = sortedLoads.first(where: { calendar.isDate($0.date, inSameDayAs: currentDate) }) {
                filledLoads.append(existing)
            } else {
                filledLoads.append(DailyTrainingLoad(date: currentDate, tss: 0))
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        let recalculated = recalculateMetrics(for: filledLoads)
        saveDailyLoads(recalculated)
        
        print("✅ Training Load: Filled to \(recalculated.count) days (\(firstDate.formatted(date: .abbreviated, time: .omitted)) to today)")
    }
    
    func debugPrintLoadData() {
        let loads = loadAllDailyLoads()
        print("\n===== TRAINING LOAD DEBUG =====")
        print("Total days with data: \(loads.count)")
        print("Storage size: \(getStorageInfo())")
        
        if loads.isEmpty {
            print("No data found!")
            return
        }
        
        let sorted = loads.sorted { $0.date < $1.date }
        print("Date range: \(sorted.first!.date.formatted(date: .abbreviated, time: .omitted)) to \(sorted.last!.date.formatted(date: .abbreviated, time: .omitted))")
        
        print("\nFirst 10 days:")
        for (index, load) in sorted.prefix(10).enumerated() {
            print("\(index + 1). \(load.date.formatted(date: .abbreviated, time: .omitted)): TSS=\(String(format: "%.1f", load.tss)), CTL=\(load.ctl.map { String(format: "%.1f", $0) } ?? "nil"), ATL=\(load.atl.map { String(format: "%.1f", $0) } ?? "nil"), TSB=\(load.tsb.map { String(format: "%.1f", $0) } ?? "nil")")
        }
        
        print("\nLast 10 days:")
        for (index, load) in sorted.suffix(10).enumerated() {
            print("\(index + 1). \(load.date.formatted(date: .abbreviated, time: .omitted)): TSS=\(String(format: "%.1f", load.tss)), CTL=\(load.ctl.map { String(format: "%.1f", $0) } ?? "nil"), ATL=\(load.atl.map { String(format: "%.1f", $0) } ?? "nil"), TSB=\(load.tsb.map { String(format: "%.1f", $0) } ?? "nil")")
        }
        
        var gapCount = 0
        for i in 0..<(sorted.count - 1) {
            let dayDiff = Calendar.current.dateComponents([.day], from: sorted[i].date, to: sorted[i + 1].date).day ?? 0
            if dayDiff > 1 {
                gapCount += 1
                if gapCount <= 5 {
                    print("⚠️ GAP: \(dayDiff - 1) days between \(sorted[i].date.formatted(date: .abbreviated, time: .omitted)) and \(sorted[i + 1].date.formatted(date: .abbreviated, time: .omitted))")
                }
            }
        }
        print("\nTotal gaps found: \(gapCount)")
        
        let nilCTL = sorted.filter { $0.ctl == nil }.count
        let nilATL = sorted.filter { $0.atl == nil }.count
        print("\nDays with nil CTL: \(nilCTL)")
        print("Days with nil ATL: \(nilATL)")
        
        print("===============================\n")
    }
    
    func getProjectedLoads(for days: Int) -> [DailyTrainingLoad] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let allLoads = loadAllDailyLoads()
        guard let latestLoad = allLoads.sorted(by: { $0.date < $1.date }).last(where: { !$0.isProjected }) else {
            return []
        }
        
        var projectedLoads: [DailyTrainingLoad] = []
        var previousATL = latestLoad.atl ?? 0
        var previousCTL = latestLoad.ctl ?? 0
        
        for i in 1...days {
            guard let futureDate = calendar.date(byAdding: .day, value: i, to: today) else { continue }
            
            let todayTSS = 0.0
            
            let atl = calculateEMA(
                previousValue: previousATL,
                newValue: todayTSS,
                days: emaATLDays
            )
            
            let ctl = calculateEMA(
                previousValue: previousCTL,
                newValue: todayTSS,
                days: emaCTLDays
            )
            
            let tsb = ctl - atl
            
            let projectedLoad = DailyTrainingLoad(
                date: futureDate,
                tss: todayTSS,
                atl: atl,
                ctl: ctl,
                tsb: tsb,
                rideCount: 0,
                totalDistance: 0,
                totalDuration: 0,
                isProjected: true
            )
            
            projectedLoads.append(projectedLoad)
            
            previousATL = atl
            previousCTL = ctl
        }
        
        return projectedLoads
    }
    
    // MARK: - Readiness Calculation
    
    /// Returns a recommended intensity multiplier (0.85 to 1.0) based on TSB and Wellness.
    /// Uses data from WellnessManager if available.
    func getCurrentReadinessFactor() -> Double {
        // 1. Base factor on Training Stress Balance (TSB)
        // Default to 1.0 (Fresh) if no data
        var factor = 1.0
        
        if let summary = getCurrentSummary() {
            let tsb = summary.currentTSB
            
            if tsb < -30 {
                print("⚠️ Training Load: Severe fatigue (TSB \(Int(tsb))). Starting at 90%.")
                factor = 0.90
            } else if tsb < -10 {
                print("⚠️ Training Load: Moderate fatigue (TSB \(Int(tsb))). Starting at 95%.")
                factor = 0.95
            }
        }
        
        // 2. Adjust based on Wellness Data (Sleep)
        // We access the singleton directly to pull the latest synced health data
        if let wellness = WellnessManager.shared.currentSummary {
            // Penalize for Sleep Debt > 4 hours
            if let sleepDebt = wellness.sleepDebt, sleepDebt < -4 {
                print("⚠️ Training Load: High sleep debt (\(Int(sleepDebt))h). reducing -3%.")
                factor -= 0.03
            }
            
            // Penalize for very poor recent sleep average (< 5h)
            if let avgSleep = wellness.averageSleepHours, avgSleep < 5.0 {
                print("⚠️ Training Load: Poor sleep avg (\(String(format: "%.1f", avgSleep))h). reducing -2%.")
                factor -= 0.02
            }
        }
        
        // Cap the reduction to prevent creating an impossibly slow plan (floor 85%)
        return max(0.85, factor)
    }
}

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
    
    // MARK: - Batch Operations (High Performance)
    
    /// Adds multiple rides efficiently by performing a single read/write cycle.
    /// Use this when syncing historical data to prevent I/O thrashing.
    func addBatchRides(_ analyses: [RideAnalysis]) {
        guard !analyses.isEmpty else { return }
        
        print("⚡️ Training Load: Batch processing \(analyses.count) rides...")
        
        // 1. Single Read
        var dailyLoads = loadAllDailyLoads()
        let calendar = Calendar.current
        
        // ✅ NEW: Track the latest date in this batch
        var latestBatchDate = Date.distantPast
        
        // 2. Memory-only processing
        for analysis in analyses {
            // Track latest
            if analysis.date > latestBatchDate {
                latestBatchDate = analysis.date
            }
            
            let rideDate = calendar.startOfDay(for: analysis.date)
            
            if let existingIndex = dailyLoads.firstIndex(where: {
                calendar.isDate($0.date, inSameDayAs: rideDate)
            }) {
                // Accumulate data efficiently
                dailyLoads[existingIndex].tss += analysis.trainingStressScore
                dailyLoads[existingIndex].rideCount += 1
                dailyLoads[existingIndex].totalDistance += analysis.distance
                dailyLoads[existingIndex].totalDuration += analysis.duration
            } else {
                // Create new entry
                let newLoad = DailyTrainingLoad(
                    date: rideDate,
                    tss: analysis.trainingStressScore,
                    rideCount: 1,
                    totalDistance: analysis.distance,
                    totalDuration: analysis.duration
                )
                dailyLoads.append(newLoad)
            }
        }
        
        // 3. Sort and Recalculate once
        dailyLoads.sort { $0.date < $1.date }
        let updatedLoads = recalculateMetrics(for: dailyLoads)
        
        // 4. Single Write
        saveDailyLoads(updatedLoads)
        
        // Update Precise Timestamp if newer
        let lastKnown = UserDefaults.standard.object(forKey: "last_ride_precise_date") as? Date ?? Date.distantPast
        if latestBatchDate > lastKnown {
            UserDefaults.standard.set(latestBatchDate, forKey: "last_ride_precise_date")
            print("\n🔎 DEBUG (Phone): Batch Import found Precise Date: \(latestBatchDate.formatted(date: .omitted, time: .standard))")
            print("🔎 DEBUG (Phone): Saving to UserDefaults 'last_ride_precise_date'\n")
            
            // Trigger sync to watch immediately
            PhoneSessionManager.shared.sendUpdate()
        } else {
            // 🔎 SEARCHLIGHT 1 (Alternative): Did we ignore it?
            print("\n🔎 DEBUG (Phone): Ignored batch date \(latestBatchDate.formatted()) because it is older than stored \(lastKnown.formatted())\n")
        }
        
        print("✅ Training Load: Successfully batch imported \(analyses.count) rides. I/O optimized.")
    }
    
    // MARK: - Batch Processing (Safe for Strava & HealthKit)
    
    /// Updates multiple days efficiently.
    /// Replaces the logic of calling updateDailyLoad() in a loop.
    /// ✅ UPDATED: Now accepts latestPreciseDate to fix Watch sync
    func updateBatchLoads(_ updates: [Date: (tss: Double, rideCount: Int, distance: Double, duration: TimeInterval)], latestPreciseDate: Date? = nil) {
        guard !updates.isEmpty else { return }
        
        print("⚡️ Training Load: Batch updating \(updates.count) days...")
        
        // 1. Single Read
        var dailyLoads = loadAllDailyLoads()
        let calendar = Calendar.current
        
        // 2. In-Memory Updates
        for (date, data) in updates {
            let dayStart = calendar.startOfDay(for: date)
            
            if let existingIndex = dailyLoads.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) {
                // MATCHES EXISTING LOGIC: Overwrite/Update values
                dailyLoads[existingIndex].tss = data.tss
                dailyLoads[existingIndex].rideCount = data.rideCount
                dailyLoads[existingIndex].totalDistance = data.distance
                dailyLoads[existingIndex].totalDuration = data.duration
            } else {
                // Create new
                dailyLoads.append(DailyTrainingLoad(
                    date: dayStart,
                    tss: data.tss,
                    rideCount: data.rideCount,
                    totalDistance: data.distance,
                    totalDuration: data.duration
                ))
            }
        }
        
        // 3. Sort & Recalculate Metrics (CTL/ATL/TSB)
        dailyLoads.sort { $0.date < $1.date }
        let updatedLoads = recalculateMetrics(for: dailyLoads)
        
        // 4. Single Write
        saveDailyLoads(updatedLoads)
        
        // 5. ✅ NEW: Save the Precise Timestamp (Fixes "19h" on Watch)
        if let newDate = latestPreciseDate {
            let lastKnown = UserDefaults.standard.object(forKey: "last_ride_precise_date") as? Date ?? Date.distantPast
            if newDate > lastKnown {
                UserDefaults.standard.set(newDate, forKey: "last_ride_precise_date")
                
                print("🔎 DEBUG (Phone): Batch Update saved precise last ride time: \(newDate.formatted(date: .omitted, time: .standard))")
                
                // Trigger sync immediately
                PhoneSessionManager.shared.sendUpdate()
            }
        }
        
        print("✅ Training Load: Batch update complete. Processed \(updates.count) days.")
    }
}
