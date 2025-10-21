//
//  EnergyCalculator.swift
//  RideWeather Pro
//

import Foundation

// MARK: - Energy Data Types

struct EnergyExpenditure {
    let segmentAnalysis: [SegmentEnergyData]
    let totalCalories: Double
    let totalCarbsCalories: Double
    let totalFatCalories: Double
    let caloriesPerHour: Double
    let carbDepletionRisk: Bool
    let metabolicSummary: MetabolicSummary
}

struct SegmentEnergyData {
    let segmentIndex: Int
    let durationMinutes: Double
    let power: Double
    let intensity: Double // % of FTP
    let mechanicalWorkKJ: Double
    let totalCalories: Double
    let carbsCalories: Double
    let fatCalories: Double
    let carbsPercent: Double
    let cumulativeCalories: Double
    let cumulativeCarbsUsed: Double
    let remainingCarbStorage: Double
}

struct MetabolicSummary {
    let averageIntensity: Double
    let timeAboveAerobicThreshold: Double // minutes
    let fatBurningEfficiency: Double // % of calories from fat
    let glycogenUtilization: Double // % of stored carbs used
    let metabolicStress: MetabolicStressRating
}

enum MetabolicStressRating: String, CaseIterable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
    case extreme = "Extreme"
    
    var color: String {
        switch self {
        case .low: return "#4CAF50"
        case .moderate: return "#FF9800"
        case .high: return "#F44336"
        case .extreme: return "#9C27B0"
        }
    }
}

// MARK: - Fueling Strategy Types

struct FuelingStrategy {
    let strategy: FuelingStrategyType
    let recommendations: [String]
    let schedule: [FuelPoint]
    let preRideFueling: PreRideFueling
    let postRideFueling: PostRideFueling
    let hydration: HydrationPlan
    let warnings: [String]
    let shoppingList: [FuelItem]
}

enum FuelingStrategyType: String, CaseIterable {
    case minimal = "Short ride - water only"
    case light = "Medium ride - light fueling"
    case structured = "Long ride - structured fueling essential"
    case comprehensive = "Ultra endurance - comprehensive strategy critical"
}

struct FuelPoint {
    let timeMinutes: Double
    let segmentIndex: Int
    let fuelType: FuelType
    let amount: String
    let product: String
    let reason: String
    let intensity: Double
}

enum FuelType: String, CaseIterable {
    case gel = "Energy Gel"
    case drink = "Sports Drink"
    case bar = "Energy Bar"
    case solid = "Solid Food"
    case electrolytes = "Electrolytes"
}

struct PreRideFueling {
    let timing: String
    let carbsAmount: String
    let recommendations: [String]
    let examples: [String]
}

struct PostRideFueling {
    let timing: String
    let carbsAmount: String
    let proteinAmount: String
    let examples: [String]
    let fullMealTiming: String
}

struct HydrationPlan {
    let totalFluidML: Double
    let fluidPerHourML: Double
    let electrolytesNeeded: Bool
    let schedule: String
    let recommendations: [String]
}

struct FuelItem {
    let item: String
    let quantity: Int
    let notes: String
    let estimatedCost: Double?
}

// MARK: - Energy Calculator

final class EnergyCalculator {
    
    private let settings: AppSettings
    private let userWeight: Double
    private let userAge: Int
    private let userGender: Gender
    private let ftp: Double
    
    // Physiological constants
    private let efficiency: Double = 0.22 // Gross mechanical efficiency
    private let carbsPerGram: Double = 4.0 // kcal/g
    private let fatPerGram: Double = 9.0 // kcal/g
    private let proteinPerGram: Double = 4.0 // kcal/g
    
    // Default carb storage (can be customized per user)
    private let carbStorageKcal: Double = 2000 // liver + muscle glycogen
    
    enum Gender: String, CaseIterable {
        case male = "Male"
        case female = "Female"
        case other = "Other"
    }
    
    init(settings: AppSettings, userAge: Int = 35, userGender: Gender = .male) {
        self.settings = settings
        self.userWeight = settings.totalWeightKg - 10 // Approximate rider weight (subtract bike)
        self.userAge = userAge
        self.userGender = userGender
        self.ftp = Double(settings.functionalThresholdPower)
    }
    
    // MARK: - Public API
    
    /// Calculate energy expenditure from paced segments
    func calculateEnergyExpenditure(from pacingPlan: PacingPlan) -> EnergyExpenditure {
        var cumulativeCalories: Double = 0
        var cumulativeCarbsBurned: Double = 0
        var cumulativeFatBurned: Double = 0
        var totalMechanicalWork: Double = 0
        
        let segmentAnalysis = pacingPlan.segments.enumerated().map { index, segment in
            let power = segment.targetPower
            let durationMinutes = segment.estimatedTimeMinutes
            
            // Calculate mechanical work (kJ)
            let mechanicalWork = (power * durationMinutes * 60) / 1000 // kJ
            totalMechanicalWork += mechanicalWork
            
            // Calculate total energy expenditure (accounting for efficiency)
            let totalEnergy = mechanicalWork / efficiency // kJ
            let calories = totalEnergy * 0.239006 // Convert kJ to kcal
            
            // Calculate substrate utilization
            let intensity = (power / ftp) * 100
            let substrateUtilization = calculateSubstrateUtilization(
                intensityPercent: intensity,
                durationMinutes: durationMinutes
            )
            
            let carbsCalories = calories * (substrateUtilization.carbsPercent / 100)
            let fatCalories = calories * (substrateUtilization.fatPercent / 100)
            
            cumulativeCalories += calories
            cumulativeCarbsBurned += carbsCalories
            cumulativeFatBurned += fatCalories
            
            return SegmentEnergyData(
                segmentIndex: index,
                durationMinutes: durationMinutes,
                power: power,
                intensity: intensity,
                mechanicalWorkKJ: mechanicalWork,
                totalCalories: calories,
                carbsCalories: carbsCalories,
                fatCalories: fatCalories,
                carbsPercent: substrateUtilization.carbsPercent,
                cumulativeCalories: cumulativeCalories,
                cumulativeCarbsUsed: cumulativeCarbsBurned,
                remainingCarbStorage: max(0, carbStorageKcal - cumulativeCarbsBurned)
            )
        }
        
        let totalDurationHours = pacingPlan.totalTimeMinutes / 60
        let caloriesPerHour = totalDurationHours > 0 ? cumulativeCalories / totalDurationHours : 0
        let carbDepletionRisk = cumulativeCarbsBurned > carbStorageKcal * 0.8
        
        let metabolicSummary = calculateMetabolicSummary(
            segments: segmentAnalysis,
            totalDuration: pacingPlan.totalTimeMinutes
        )
        
        return EnergyExpenditure(
            segmentAnalysis: segmentAnalysis,
            totalCalories: cumulativeCalories,
            totalCarbsCalories: cumulativeCarbsBurned,
            totalFatCalories: cumulativeFatBurned,
            caloriesPerHour: caloriesPerHour,
            carbDepletionRisk: carbDepletionRisk,
            metabolicSummary: metabolicSummary
        )
    }
    
    /// Generate comprehensive fueling strategy
    private func generateFuelingSchedule(
        segments: [SegmentEnergyData],
        maxCarbsPerHour: Double,
        availableFuelTypes: [FuelType]
    ) -> [FuelPoint] {
        
        var schedule: [FuelPoint] = []
        var cumulativeTime: Double = 0
        var lastFuelTime: Double = 0
        let targetFuelInterval: Double = 17.5 // Average of 15-20 minutes
        let firstFuelDelay: Double = 15.0 // Start fueling at 15 minutes
        
        for (index, segment) in segments.enumerated() {
            cumulativeTime += segment.durationMinutes
            
            // Check if it's time to fuel
            // Start at 15 min, then every 15-20 min after
            let timeSinceLastFuel = cumulativeTime - lastFuelTime
            let shouldFuel = (lastFuelTime == 0 && cumulativeTime >= firstFuelDelay) ||
            (lastFuelTime > 0 && timeSinceLastFuel >= targetFuelInterval)
            
            if shouldFuel {
                // Standard gel size - don't force double gels
                let carbsPerGel = 22.0
                let fuelType = selectOptimalFuelType(
                    intensity: segment.intensity,
                    availableTypes: availableFuelTypes
                )
                
                // Determine reason based on ride progress
                let reason: String
                if segment.intensity > 85 {
                    reason = "High intensity - maintain energy"
                } else if segment.remainingCarbStorage < 500 {
                    reason = "Glycogen preservation"
                } else if cumulativeTime < 60 {
                    reason = "Early ride fueling"
                } else {
                    reason = "Regular intake schedule"
                }
                
                schedule.append(FuelPoint(
                    timeMinutes: cumulativeTime,
                    segmentIndex: index,
                    fuelType: fuelType,
                    amount: "\(Int(carbsPerGel))g carbs",
                    product: generateProductExample(for: fuelType, carbsNeeded: carbsPerGel),
                    reason: reason,
                    intensity: segment.intensity
                ))
                
                lastFuelTime = cumulativeTime
            }
        }
        
        return schedule
    }
    
    func generateFuelingStrategy(
        from energyExpenditure: EnergyExpenditure,
        preferences: FuelingPreferences = FuelingPreferences()
    ) -> FuelingStrategy {
        
        let totalDuration = energyExpenditure.segmentAnalysis.reduce(0) { $0 + $1.durationMinutes }
        let strategyType = determineFuelingStrategyType(durationMinutes: totalDuration)
        
        let recommendations = generateRecommendations(
            energyExpenditure: energyExpenditure,
            preferences: preferences
        )
        
        let schedule = generateFuelingSchedule(
            segments: energyExpenditure.segmentAnalysis,
            maxCarbsPerHour: preferences.maxCarbsPerHour,
            availableFuelTypes: preferences.fuelTypes
        )
        
        let preRide = generatePreRideFueling(durationMinutes: totalDuration)
        let postRide = generatePostRideFueling(energyExpenditure: energyExpenditure)
        let hydration = calculateHydrationNeeds(
            durationMinutes: totalDuration,
            caloriesPerHour: energyExpenditure.caloriesPerHour
        )
        
        let warnings = generateWarnings(
            energyExpenditure: energyExpenditure,
            totalDuration: totalDuration
        )
        
        let shoppingList = generateShoppingList(schedule: schedule)
        
        return FuelingStrategy(
            strategy: strategyType,
            recommendations: recommendations,
            schedule: schedule,
            preRideFueling: preRide,
            postRideFueling: postRide,
            hydration: hydration,
            warnings: warnings,
            shoppingList: shoppingList
        )
    }
    
    // MARK: - Private Implementation
    
    private func calculateSubstrateUtilization(intensityPercent: Double, durationMinutes: Double) -> (carbsPercent: Double, fatPercent: Double) {
        let intensityFactor = intensityPercent / 100.0
        
        var fatPercent: Double
        var carbsPercent: Double
        
        // Base substrate utilization based on intensity (Brooks & Mercier crossover concept)
        if intensityFactor < 0.65 {
            // Low intensity - primarily fat burning
            fatPercent = 85 - (intensityFactor * 20)
        } else if intensityFactor < 0.85 {
            // Moderate intensity - mixed utilization
            fatPercent = 50 - ((intensityFactor - 0.65) * 100)
        } else {
            // High intensity - primarily carbohydrate
            fatPercent = max(5, 25 - ((intensityFactor - 0.85) * 80))
        }
        
        carbsPercent = 100 - fatPercent
        
        // Duration effect - longer efforts shift toward more fat utilization
        if durationMinutes > 90 {
            let durationFactor = min(0.2, (durationMinutes - 90) / 300)
            fatPercent += durationFactor * 100
            carbsPercent = 100 - fatPercent
        }
        
        return (
            carbsPercent: max(5, min(95, carbsPercent)),
            fatPercent: max(5, min(95, fatPercent))
        )
    }
    
    private func calculateMetabolicSummary(segments: [SegmentEnergyData], totalDuration: Double) -> MetabolicSummary {
        let totalCalories = segments.reduce(0) { $0 + $1.totalCalories }
        let totalCarbsCalories = segments.reduce(0) { $0 + $1.carbsCalories }
        let totalFatCalories = segments.reduce(0) { $0 + $1.fatCalories }
        
        let averageIntensity = segments.reduce(0) { $0 + ($1.intensity * $1.durationMinutes) } / totalDuration
        
        let timeAboveAT = segments
            .filter { $0.intensity > 85 } // Above aerobic threshold (~85% FTP)
            .reduce(0) { $0 + $1.durationMinutes }
        
        let fatBurningEfficiency = totalCalories > 0 ? (totalFatCalories / totalCalories) * 100 : 0
        let glycogenUtilization = (totalCarbsCalories / carbStorageKcal) * 100
        
        let metabolicStress = assessMetabolicStress(
            averageIntensity: averageIntensity,
            duration: totalDuration,
            glycogenUtilization: glycogenUtilization
        )
        
        return MetabolicSummary(
            averageIntensity: averageIntensity,
            timeAboveAerobicThreshold: timeAboveAT,
            fatBurningEfficiency: fatBurningEfficiency,
            glycogenUtilization: glycogenUtilization,
            metabolicStress: metabolicStress
        )
    }
    
    private func assessMetabolicStress(averageIntensity: Double, duration: Double, glycogenUtilization: Double) -> MetabolicStressRating {
        if averageIntensity > 90 || duration > 240 || glycogenUtilization > 90 {
            return .extreme
        } else if averageIntensity > 80 || duration > 180 || glycogenUtilization > 70 {
            return .high
        } else if averageIntensity > 70 || duration > 90 || glycogenUtilization > 50 {
            return .moderate
        } else {
            return .low
        }
    }
    
    private func determineFuelingStrategyType(durationMinutes: Double) -> FuelingStrategyType {
        if durationMinutes < 60 {
            return .minimal
        } else if durationMinutes < 90 {
            return .light
        } else if durationMinutes < 180 {
            return .structured
        } else {
            return .comprehensive
        }
    }
    
    private func selectOptimalFuelType(intensity: Double, availableTypes: [FuelType]) -> FuelType {
        return .gel
    }
    
    private func generateProductExample(for fuelType: FuelType, carbsNeeded: Double) -> String {
        return "Energy gel (22g carbs)"
    }
    
    private func generateRecommendations(
        energyExpenditure: EnergyExpenditure,
        preferences: FuelingPreferences
    ) -> [String] {
        var recommendations: [String] = []
        
        let totalDuration = energyExpenditure.segmentAnalysis.reduce(0) { $0 + $1.durationMinutes }
        let carbsPerHour = (energyExpenditure.totalCarbsCalories / carbsPerGram) / (totalDuration / 60)
        
        recommendations.append("Ride will burn roughly \(Int(carbsPerHour))g carbs/hour")
        
        if energyExpenditure.caloriesPerHour > 800 {
            recommendations.append("High intensity - prioritize easily digestible carbs")
        }
        
        if totalDuration > 120 {
            recommendations.append("Long ride - mix fuel types to prevent flavor fatigue")
        }
        
        if energyExpenditure.carbDepletionRisk {
            recommendations.append("⚠️ High glycogen depletion risk - increase fueling frequency")
        }
        
        if energyExpenditure.metabolicSummary.fatBurningEfficiency < 30 {
            recommendations.append("Low fat burning efficiency - consider aerobic base training")
        }
        
        return recommendations
    }
    
    private func generatePreRideFueling(durationMinutes: Double) -> PreRideFueling {
        if durationMinutes < 60 {
            return PreRideFueling(
                timing: "2-3 hours before",
                carbsAmount: "Normal meal",
                recommendations: ["No special fueling needed", "Ensure adequate hydration"],
                examples: ["Regular breakfast", "Toast with jam", "Oatmeal with fruit"]
            )
        } else if durationMinutes < 180 {
            return PreRideFueling(
                timing: "2-3 hours before + 30min before",
                carbsAmount: "Normal meal + 30-60g carbs",
                recommendations: ["Carb-rich meal 2-3 hours prior", "Top up 30min before start"],
                examples: ["Oatmeal + banana", "Toast + honey + coffee", "Energy bar 30min before"]
            )
        } else {
            return PreRideFueling(
                timing: "2-3 days + 3 hours + 30min before",
                carbsAmount: "Carb loading + large breakfast + 60g carbs",
                recommendations: ["Carb loading 2-3 days prior", "Large breakfast 3 hours before", "Final top-up 30min before"],
                examples: ["Pasta loading", "Large porridge breakfast", "2x energy gels before start"]
            )
        }
    }
    
    private func generatePostRideFueling(energyExpenditure: EnergyExpenditure) -> PostRideFueling {
        let recoveryCarbs = min(100, energyExpenditure.totalCarbsCalories / carbsPerGram * 0.3)
        let recoveryProtein = recoveryCarbs / 3
        
        return PostRideFueling(
            timing: "Within 30 minutes",
            carbsAmount: "\(Int(recoveryCarbs))g carbs",
            proteinAmount: "\(Int(recoveryProtein))g protein",
            examples: ["Chocolate milk", "Recovery shake", "Greek yogurt with fruit"],
            fullMealTiming: "Complete meal within 2 hours"
        )
    }
    
    private func calculateHydrationNeeds(durationMinutes: Double, caloriesPerHour: Double) -> HydrationPlan {
        // Base fluid needs: ~150-250ml per 15 minutes
        let baseFluidML = durationMinutes * 12 // 180ml per 15min average
        
        // Intensity adjustment
        let intensityMultiplier = max(1.0, min(1.5, caloriesPerHour / 600))
        let totalFluidML = baseFluidML * intensityMultiplier
        
        let fluidPerHourML = totalFluidML / (durationMinutes / 60)
        let electrolytesNeeded = durationMinutes > 60
        
        let schedule = "Drink \(Int(totalFluidML / max(1, durationMinutes / 15)))ml every 15 minutes"
        
        var recommendations = ["Start hydrating before you feel thirsty"]
        if electrolytesNeeded {
            recommendations.append("Add electrolytes for rides >1 hour")
        }
        if durationMinutes > 240 {
            recommendations.append("Monitor urine color for hydration status")
        }
        
        return HydrationPlan(
            totalFluidML: totalFluidML,
            fluidPerHourML: fluidPerHourML,
            electrolytesNeeded: electrolytesNeeded,
            schedule: schedule,
            recommendations: recommendations
        )
    }
    
    private func generateWarnings(energyExpenditure: EnergyExpenditure, totalDuration: Double) -> [String] {
        var warnings: [String] = []
        
        if energyExpenditure.carbDepletionRisk {
            warnings.append("⚠️ Risk of glycogen depletion - increase carb intake")
        }
        
        if energyExpenditure.caloriesPerHour > 1000 {
            warnings.append("⚠️ Very high intensity - monitor for GI distress")
        }
        
        if totalDuration > 240 {
            warnings.append("⚠️ Ultra distance - consider sodium replacement")
        }
        
        if energyExpenditure.totalCalories > 2000 {
            warnings.append("⚠️ High energy demand - plan multiple fuel sources")
        }
        
        if energyExpenditure.metabolicSummary.timeAboveAerobicThreshold > 60 {
            warnings.append("⚠️ Extended time above aerobic threshold - pace conservatively")
        }
        
        return warnings
    }
    
    private func generateShoppingList(schedule: [FuelPoint]) -> [FuelItem] {
        var itemCounts: [FuelType: Int] = [:]
        
        for fuelPoint in schedule {
            itemCounts[fuelPoint.fuelType, default: 0] += 1
        }
        
        return itemCounts.map { fuelType, count in
            FuelItem(
                item: fuelType.rawValue,
                quantity: count,
                notes: "For \(count) feeding points during ride",
                estimatedCost: estimateCost(for: fuelType, quantity: count)
            )
        }.sorted { $0.item < $1.item }
    }
    
    private func estimateCost(for fuelType: FuelType, quantity: Int) -> Double {
        let unitCosts: [FuelType: Double] = [
            .gel: 2.50,
            .drink: 1.00,
            .bar: 3.00,
            .solid: 0.50,
            .electrolytes: 0.75
        ]
        
        return (unitCosts[fuelType] ?? 2.0) * Double(quantity)
    }
}

// MARK: - Fueling Preferences

struct FuelingPreferences {
    let maxCarbsPerHour: Double
    let fuelTypes: [FuelType]
    let preferLiquids: Bool
    let avoidGluten: Bool
    let avoidCaffeine: Bool
    
    init(
        maxCarbsPerHour: Double = 60,
        fuelTypes: [FuelType] = [.gel, .drink, .bar, .solid],
        preferLiquids: Bool = false,
        avoidGluten: Bool = false,
        avoidCaffeine: Bool = false
    ) {
        self.maxCarbsPerHour = maxCarbsPerHour
        self.fuelTypes = fuelTypes
        self.preferLiquids = preferLiquids
        self.avoidGluten = avoidGluten
        self.avoidCaffeine = avoidCaffeine
    }
}

// MARK: - Export Extensions

extension FuelingStrategy {
    
    /// Export fueling schedule as CSV
    func exportScheduleAsCSV() -> String {
        let headers = ["Time_min", "Segment", "Fuel_Type", "Amount", "Product", "Reason", "Intensity_%"]
        
        let rows = schedule.map { fuelPoint in
            [
                String(format: "%.0f", fuelPoint.timeMinutes),
                String(fuelPoint.segmentIndex + 1),
                fuelPoint.fuelType.rawValue,
                fuelPoint.amount,
                fuelPoint.product,
                fuelPoint.reason,
                String(format: "%.0f", fuelPoint.intensity)
            ].joined(separator: ",")
        }
        
        return ([headers.joined(separator: ",")] + rows).joined(separator: "\n")
    }
}

