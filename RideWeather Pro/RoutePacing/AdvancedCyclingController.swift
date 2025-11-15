//
//  AdvancedCyclingController.swift - FIXED VERSION
//  RideWeather Pro
//

import Foundation
import SwiftUI
import CoreLocation
import Combine

// MARK: - Main Integration Controller

@MainActor
final class AdvancedCyclingController: ObservableObject {
    
    // MARK: - Published Properties
    @Published var pacingPlan: PacingPlan?
    @Published var energyExpenditure: EnergyExpenditure?
    @Published var fuelingStrategy: FuelingStrategy?
    @Published var isGeneratingPlan = false
//    @Published var syncResults: [SyncResult] = []
    
    // MARK: - Components
    private var pacingEngine: PacingEngine
    private var energyCalculator: EnergyCalculator
//    private var deviceSyncManager: DeviceSyncManager
    private let settings: AppSettings
    
    // MARK: - Initialization
    
    init(settings: AppSettings) {
        self.settings = settings
        self.pacingEngine = PacingEngine(settings: settings)
        self.energyCalculator = EnergyCalculator(settings: settings)
 //       self.deviceSyncManager = DeviceSyncManager()
    }
    
    // MARK: - Main Workflow
    
    /// Generate comprehensive race plan from power analysis results
    func generateAdvancedRacePlan(
        from powerAnalysis: PowerRouteAnalysisResult,
        strategy: PacingStrategy = .balanced,
        fuelingPreferences: FuelingPreferences = FuelingPreferences(),
        startTime: Date = Date().addingTimeInterval(7200), // 2 hours from now
        routeName: String = "My Route"  // ✅ ADD THIS PARAMETER
    ) async {
        
        isGeneratingPlan = true
        
        print("🚴‍♂️ Generating advanced race plan...")
        
        // Step 1: Generate pacing plan
        print("📊 Calculating optimal pacing strategy...")
        let pacing = pacingEngine.generatePacingPlan(
            from: powerAnalysis,
            strategy: strategy,
            startTime: startTime
        )
        
        // Step 2: Calculate energy expenditure
        print("⚡ Analyzing energy requirements...")
        let energy = energyCalculator.calculateEnergyExpenditure(from: pacing)
        
        // Step 3: Generate fueling strategy
        print("🌟 Creating fueling strategy...")
        let fueling = energyCalculator.generateFuelingStrategy(
            from: energy,
            preferences: fuelingPreferences
        )
        
        // ✅ SAVE THE PLAN AUTOMATICALLY
        self.savePacingPlan(pacing, routeName: routeName)  // FIX: Use 'self' and pass routeName
        
        // Update published properties
        self.pacingPlan = pacing
        self.energyExpenditure = energy
        self.fuelingStrategy = fueling
        
        print("✅ Advanced race plan generated successfully!")
        print("📈 \(String(format: "%.1f", pacing.totalDistance))km in \(formatDuration(pacing.totalTimeMinutes * 60))")
        print("⚡ \(Int(energy.totalCalories)) calories, \(Int(pacing.estimatedTSS)) TSS")
        
        isGeneratingPlan = false
    }
       
    // MARK: - Export Functions
    
    /// Export complete race plan as CSV
    func exportPacingPlanCSV(using pacingPlan: PacingPlan) -> String {
        guard let energy = energyExpenditure else {
            return "Energy data not available"
        }

        let headers = [
            "Segment", "Distance_km", "Gradient_%", "Target_Power_W", "Power_Zone",
            "Est_Time_min", "Calories", "Carbs_kcal", "Cumulative_Time_min",
            "Cumulative_Distance_km", "Strategy_Notes"
        ]
        
        var cumulativeTime: Double = 0
        var cumulativeDistance: Double = 0
        
        let rows = pacingPlan.segments.enumerated().map { index, pacingSeg in
            cumulativeTime += pacingSeg.estimatedTimeMinutes
            cumulativeDistance += pacingSeg.distanceKm
            
            let energySeg = energy.segmentAnalysis[safe: index]
            
            return [
                String(index + 1),
                String(format: "%.3f", pacingSeg.distanceKm),
                String(format: "%.1f", pacingSeg.originalSegment.elevationGrade * 100),
                String(Int(pacingSeg.targetPower)),
                pacingSeg.powerZone.name,
                String(format: "%.1f", pacingSeg.estimatedTimeMinutes),
                String(Int(energySeg?.totalCalories ?? 0)),
                String(Int(energySeg?.carbsCalories ?? 0)),
                String(format: "%.1f", cumulativeTime),
                String(format: "%.2f", cumulativeDistance),
                pacingSeg.strategy
            ].joined(separator: ",")
        }
        
        return ([headers.joined(separator: ",")] + rows).joined(separator: "\n")
    }
    
    func generateRaceDaySummary(using pacingPlan: PacingPlan) -> String {
        guard let energy = energyExpenditure,
              let fueling = fuelingStrategy else {
            return "No race plan available"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        
        var summary = """
        ═══════════════════════════════════════════════
        RACE DAY PLAN - \(formatter.string(from: Date()))
        ═══════════════════════════════════════════════
        
        📍 ROUTE OVERVIEW
        ─────────────────────────────────────────────
        Distance:        \(String(format: "%.2f km", pacingPlan.totalDistance))
        Estimated Time:  \(formatDuration(pacingPlan.totalTimeMinutes * 60))
        Start Time:      \(formatter.string(from: pacingPlan.startTime))
        Arrival:         \(formatter.string(from: pacingPlan.estimatedArrival))
        
        ⚡ POWER TARGETS
        ─────────────────────────────────────────────
        Strategy:        \(pacingPlan.strategy.description)
        Normalized Power: \(Int(pacingPlan.normalizedPower)) W
        Average Power:   \(Int(pacingPlan.averagePower)) W
        Intensity Factor: \(String(format: "%.2f", pacingPlan.intensityFactor))
        TSS:             \(Int(pacingPlan.estimatedTSS))
        
        🔥 ENERGY DEMANDS
        ─────────────────────────────────────────────
        Total Calories:  \(Int(energy.totalCalories)) kcal
        Calories/Hour:   \(Int(energy.caloriesPerHour)) kcal/h
        Carbs Needed:    \(Int(energy.totalCarbsCalories / 4))g
        Fat Utilization: \(Int(energy.totalFatCalories / energy.totalCalories * 100))%
        
        """
        
        // Critical timing section
        summary += """
        ⏰ CRITICAL TIMINGS (SET ALARMS!)
        ─────────────────────────────────────────────
        
        """
        
        // Pre-ride timing
        let preRideTime = pacingPlan.startTime.addingTimeInterval(-10800) // 3 hours before
        formatter.timeStyle = .short
        summary += "☕ \(formatter.string(from: preRideTime)) - Pre-ride meal\n"
        summary += "   → \(fueling.preRideFueling.carbsAmount)\n"
        summary += "   → Examples: \(fueling.preRideFueling.examples.prefix(2).joined(separator: ", "))\n\n"
        
        let finalFuelTime = pacingPlan.startTime.addingTimeInterval(-1800) // 30 min before
        summary += "🎯 \(formatter.string(from: finalFuelTime)) - Final fuel top-up\n"
        summary += "   → 30-60g fast carbs (gel or drink)\n\n"
        
        // During-ride fueling with actual times
        summary += "🌟 DURING RIDE - FUELING SCHEDULE\n"
        summary += "────────────────────────────────────────────────\n"
        
        for (index, fuelPoint) in fueling.schedule.enumerated() {
            let fuelTime = pacingPlan.startTime.addingTimeInterval(fuelPoint.timeMinutes * 60)
            let icon = fuelIcon(for: fuelPoint.fuelType)
            summary += "\n\(icon) \(formatter.string(from: fuelTime)) (\(Int(fuelPoint.timeMinutes))min into ride)\n"
            summary += "   → \(fuelPoint.amount) - \(fuelPoint.product)\n"
            summary += "   → \(fuelPoint.reason) (Intensity: \(Int(fuelPoint.intensity))%)\n"
        }
        
        if fueling.schedule.isEmpty {
            summary += "\n⚠️  No fueling points scheduled - ride duration may be too short\n"
        }
        
        summary += "\nℹ️  TIP: Set 15-20 minute timer for consistent fueling\n"
        
        if fueling.schedule.count > 10 {
            summary += "\n   ... plus \(fueling.schedule.count - 10) more fuel points\n"
        }
        
        // Hydration
        summary += """
        
        
        💧 HYDRATION STRATEGY
        ─────────────────────────────────────────────
        Total Fluid:     \(String(format: "%.1f L", fueling.hydration.totalFluidML / 1000))
        Per Hour:        \(Int(fueling.hydration.fluidPerHourML)) ml/h
        Schedule:        \(fueling.hydration.schedule)
        Electrolytes:    \(fueling.hydration.electrolytesNeeded ? "✓ Required" : "Not needed")
        
        TIP: Set a 15-minute repeating alarm for hydration reminders
        
        """
        
        // Post-ride timing
        let finishTime = pacingPlan.estimatedArrival
        let recoveryWindowEnd = finishTime.addingTimeInterval(1800) // 30 min window
        summary += "🔄 POST-RIDE RECOVERY\n"
        summary += "─────────────────────────────────────────────\n"
        summary += "⏱️  Within 30 min of finish (\(formatter.string(from: finishTime)) - \(formatter.string(from: recoveryWindowEnd)))\n"
        summary += "   → \(fueling.postRideFueling.carbsAmount) + \(fueling.postRideFueling.proteinAmount)\n"
        summary += "   → Examples: \(fueling.postRideFueling.examples.joined(separator: ", "))\n"
        summary += "\n🍽️  Full meal: \(fueling.postRideFueling.fullMealTiming)\n\n"
        
        // Warnings section
        if !fueling.warnings.isEmpty || energy.carbDepletionRisk {
            summary += "⚠️  IMPORTANT WARNINGS\n"
            summary += "─────────────────────────────────────────────\n"
            for warning in fueling.warnings {
                summary += "• \(warning)\n"
            }
            if energy.carbDepletionRisk {
                summary += "• HIGH GLYCOGEN DEPLETION RISK - Do not skip fueling!\n"
            }
            summary += "\n"
        }
        
        // Shopping list
        summary += "🛒 SHOPPING LIST\n"
        summary += "─────────────────────────────────────────────\n"
        var totalCost = 0.0
        for item in fueling.shoppingList {
            let cost = item.estimatedCost ?? 0
            totalCost += cost
            summary += "□ \(item.quantity)x \(item.item)"
            if cost > 0 {
                summary += " (~$\(String(format: "%.2f", cost)))"
            }
            summary += "\n"
        }
        summary += "\nEstimated Total: $\(String(format: "%.2f", totalCost))\n\n"
        
        // Pre-departure checklist
        summary += """
        ✅ PRE-DEPARTURE CHECKLIST
        ─────────────────────────────────────────────
        □ All fuel/nutrition packed and accessible
        □ Bottles filled with correct mix
        □ Device synced and charged (>80% battery)
        □ Weather-appropriate clothing
        □ Power meter calibrated
        □ Alarms set for key timings
        □ Backup fuel in pocket
        □ Emergency contact info saved
        
        📱 DEVICE REMINDERS
        ─────────────────────────────────────────────
        • Check power targets every 5-10 minutes
        • Stay in prescribed zones - resist going harder!
        • Fuel before feeling hungry
        • If power meter fails: use HR zones + perceived effort
        
        ═══════════════════════════════════════════════
        Generated by RideWeather Pro
        \(Date().formatted(date: .abbreviated, time: .shortened))
        ═══════════════════════════════════════════════
        """
        
// temporary print statement
        print(summary)

        return summary
    }

    private func fuelIcon(for type: FuelType) -> String {
        switch type {
        case .gel: return "🟠"
        case .drink: return "🔵"
        case .bar: return "🟤"
        case .solid: return "🟢"
        case .electrolytes: return "🟣"
        }
    }
    
    // MARK: - Utility Functions
    
    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)min"
        } else {
            return "\(minutes)min"
        }
    }
}

// MARK: - Helper Extensions

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension AdvancedCyclingController {
    
    /// Generates a Garmin Course FIT file with power targets
    func generateGarminCourseFIT(
        pacingPlan: PacingPlan,
        routePoints: [EnhancedRoutePoint],
        courseName: String? = nil,
        includeRecordMessages: Bool = true // <-- ADD THIS
    ) throws -> Data? {
                
        let generator = GarminCourseFitGenerator()
        let name = courseName ?? "RideWeather Pro Course"
        
        let fitData = try generator.generateCourseFIT(
            routePoints: routePoints,
            pacingPlan: pacingPlan,
            courseName: name,
            settings: settings,
            includeRecordMessages: includeRecordMessages // <-- PASS IT THROUGH
        )
        
        return fitData
    }
}

extension AdvancedCyclingController {
    
    private var planStorageKey: String { "savedPacingPlans" }
    
    // Save plan after generation
    func savePacingPlan(_ plan: PacingPlan, routeName: String) {
        // Append strategy abbreviation to route name
        let strategyAbbrev: String
        switch plan.strategy {
        case .balanced: strategyAbbrev = "bal"
        case .conservative: strategyAbbrev = "con"
        case .aggressive: strategyAbbrev = "agg"
        case .negativeSplit: strategyAbbrev = "neg"
        case .evenEffort: strategyAbbrev = "even"
        }
        
        let planWrapper = StoredPacingPlan(
            id: UUID(),
            routeName: "\(routeName) (\(strategyAbbrev))",  // ✅ Strategy appended here
            plan: plan,
            createdDate: Date()
        )
        
        var plans = loadSavedPlans()
        plans.append(planWrapper)
        
        // Keep last 20 plans
        if plans.count > 20 {
            plans = Array(plans.suffix(20))
        }
        
        if let encoded = try? JSONEncoder().encode(plans) {
            UserDefaults.standard.set(encoded, forKey: planStorageKey)
        }
        
        print("✅ Pacing plan saved: \(routeName)")
    }
    
    func loadSavedPlans() -> [StoredPacingPlan] {
        guard let data = UserDefaults.standard.data(forKey: planStorageKey),
              let plans = try? JSONDecoder().decode([StoredPacingPlan].self, from: data) else {
            return []
        }
        return plans.sorted { $0.createdDate > $1.createdDate }
    }
    
    func deletePlan(_ plan: StoredPacingPlan) {
        var plans = loadSavedPlans()
        plans.removeAll { $0.id == plan.id }
        
        if let encoded = try? JSONEncoder().encode(plans) {
            UserDefaults.standard.set(encoded, forKey: planStorageKey)
        }
    }
}

struct StoredPacingPlan: Codable, Identifiable {
    let id: UUID
    let routeName: String
    let plan: PacingPlan
    let createdDate: Date
}
