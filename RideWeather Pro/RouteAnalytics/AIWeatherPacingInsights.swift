//
//  AIWeatherPacingInsights.swift
//  RideWeather Pro
//
//  AI-powered weather-pacing insights for strategic guidance
//

import Foundation
import SwiftUI
import CoreLocation

// MARK: - Main Insights Engine

struct AIWeatherPacingInsights {
    let pacingPlan: PacingPlan?
    let powerAnalysis: PowerRouteAnalysisResult?
    let weatherPoints: [RouteWeatherPoint]
    let settings: AppSettings
    let elevationAnalysis: ElevationAnalysis?
    
    // Wind significance thresholds
    private struct WindThresholds {
        static let minMeaningfulWind: Double = 8.0      // mph/kph - ignore below this
        static let significantWind: Double = 15.0       // Strong wind
        static let veryStrongWind: Double = 25.0        // Very strong wind
        static let powerSavingsThreshold: Double = 6.0  // Minimum wind change to mention
    }
    
    func generateInsights() -> WeatherPacingInsightResult? {
        // Only generate insights if we have power analysis
        guard let powerAnalysis = powerAnalysis else { return nil }
        
        let criticalSegments = identifyCriticalWeatherSegments(powerSegments: powerAnalysis.segments)
        let strategicGuidance = generateStrategicGuidance(powerSegments: powerAnalysis.segments)
        let overallRecommendation = generateOverallRecommendation(powerSegments: powerAnalysis.segments)
        
        // Only return if we have meaningful insights
        guard !criticalSegments.isEmpty || !strategicGuidance.isEmpty || !overallRecommendation.isEmpty else {
            return nil
        }
        
        return WeatherPacingInsightResult(
            criticalSegments: criticalSegments,
            strategicGuidance: strategicGuidance,
            overallRecommendation: overallRecommendation
        )
    }
    
    // MARK: - Critical Segment Identification
    
    private func identifyCriticalWeatherSegments(powerSegments: [PowerRouteSegment]) -> [CriticalWeatherSegment] {
        var segments: [(segment: CriticalWeatherSegment, severity: Double)] = []
        
        // Track overall route conditions to avoid repetition
        let avgTemp = powerSegments.map { $0.averageTemperatureC }.reduce(0, +) / Double(powerSegments.count)
        let routeIsGenerallyCold = (settings.units == .metric ? avgTemp : (avgTemp * 9/5 + 32)) < (settings.units == .metric ? 10 : 50)
        let routeIsGenerallyHot = (settings.units == .metric ? avgTemp : (avgTemp * 9/5 + 32)) > (settings.units == .metric ? 28 : 82)
        
        for (index, powerSeg) in powerSegments.enumerated() {
            var severityScore = 0.0
            var conditions: [String] = []
            var powerAdjustments: [String] = []
            var strategicNotes: [String] = []
            
            let windSpeed = abs(powerSeg.averageHeadwindMps) + abs(powerSeg.averageCrosswindMps)
            let windSpeedUserUnits = windSpeed * (settings.units == .metric ? 3.6 : 2.237)
            let temp = settings.units == .metric ?
                powerSeg.averageTemperatureC :
                (powerSeg.averageTemperatureC * 9/5 + 32)
            let humidity = Int(powerSeg.averageHumidity)
            
            // --- PRECIPITATION ANALYSIS ---
            if let weatherPoint = findClosestWeatherPoint(to: powerSeg, in: weatherPoints) {
                if weatherPoint.weather.pop >= 0.6 {
                    severityScore += 6.0
                    conditions.append("High rain chance (\(Int(weatherPoint.weather.pop * 100))%)")
                    strategicNotes.append("🌧️ Rain likely - reduce cornering speed, increase braking distance")
                    powerAdjustments.append("Expect 5-10% speed reduction in wet conditions")
                } else if weatherPoint.weather.pop >= 0.3 {
                    severityScore += 3.0
                    conditions.append("Possible rain (\(Int(weatherPoint.weather.pop * 100))%)")
                    strategicNotes.append("🌦️ Pack rain gear, have backup plan")
                }
            }
            
            // --- HEADWIND ANALYSIS ---
            if powerSeg.averageHeadwindMps > 3.0 {
                let headwindSpeed = powerSeg.averageHeadwindMps * (settings.units == .metric ? 3.6 : 2.237)
                
                if headwindSpeed > WindThresholds.veryStrongWind {
                    severityScore += 9.0
                    conditions.append("Very strong \(Int(headwindSpeed))\(settings.units.speedUnitAbbreviation) headwind")
                    
                    // The pacing plan ALREADY accounts for wind in its power calculation
                    // So instead of saying "add X watts", explain the situation
                    let userFTP = Double(settings.functionalThresholdPower)
                    let currentPower = powerSeg.powerRequired
                    let powerAsPercentFTP = (currentPower / userFTP) * 100
                    
                    if powerAsPercentFTP > 90 {
                        // Already pushing very hard
                        powerAdjustments.append("Plan targets \(Int(currentPower))W (\(Int(powerAsPercentFTP))% FTP)")
                        strategicNotes.append("⚠️ CRITICAL: Already at threshold intensity due to headwind")
                        strategicNotes.append("Cannot push harder - focus on aerodynamics and pacing")
                    } else if powerAsPercentFTP > 75 {
                        // Moderate effort
                        powerAdjustments.append("Plan targets \(Int(currentPower))W (\(Int(powerAsPercentFTP))% FTP)")
                        strategicNotes.append("Tempo effort required to maintain pace in headwind")
                        
                        // Calculate how much extra power is available if they want to push
                        let maxSustainablePower = userFTP * 0.95
                        let availablePower = max(0, maxSustainablePower - currentPower)
                        if availablePower > 20 {
                            strategicNotes.append("Could add up to \(Int(availablePower))W if trying to minimize time loss")
                        }
                    } else {
                        // Lower effort
                        powerAdjustments.append("Plan targets \(Int(currentPower))W (\(Int(powerAsPercentFTP))% FTP)")
                        strategicNotes.append("Manageable headwind - maintain steady effort")
                    }
                    
                    if powerSeg.elevationGrade > 0.03 {
                        severityScore += 3.0
                        strategicNotes.append("Headwind + climb = compound difficulty")
                    }
                    
                } else if headwindSpeed > WindThresholds.significantWind {
                    severityScore += 5.0
                    conditions.append("Strong \(Int(headwindSpeed))\(settings.units.speedUnitAbbreviation) headwind")
                    
                    let userFTP = Double(settings.functionalThresholdPower)
                    let currentPower = powerSeg.powerRequired
                    let powerAsPercentFTP = (currentPower / userFTP) * 100
                    
                    powerAdjustments.append("Plan targets \(Int(currentPower))W (\(Int(powerAsPercentFTP))% FTP)")
                    
                    if powerAsPercentFTP > 85 {
                        strategicNotes.append("High intensity due to headwind - pace carefully")
                    } else {
                        strategicNotes.append("Steady effort into headwind - stay aero")
                    }
                }
            }
            
            // --- TAILWIND ANALYSIS ---
            else if powerSeg.averageHeadwindMps < -3.0 {
                let tailwindSpeed = abs(powerSeg.averageHeadwindMps) * (settings.units == .metric ? 3.6 : 2.237)
                
                if tailwindSpeed > WindThresholds.significantWind {
                    severityScore += 3.0
                    conditions.append("Strong \(Int(tailwindSpeed))\(settings.units.speedUnitAbbreviation) tailwind")
                    
                    let powerSavings = calculateTailwindPowerBonus(
                        tailwindSpeed: tailwindSpeed,
                        riderSpeed: powerSeg.calculatedSpeedMps * (settings.units == .metric ? 3.6 : 2.237)
                    )
                    
                    powerAdjustments.append("Can reduce \(Int(powerSavings))W while maintaining speed")
                    strategicNotes.append("💨 Recovery opportunity - refuel and prepare for next effort")
                    
                    if powerSeg.elevationGrade < -0.02 {
                        strategicNotes.append("Tailwind + descent = free speed, focus on position/hydration")
                    }
                }
            }
            
            // --- CROSSWIND ANALYSIS ---
            if abs(powerSeg.averageCrosswindMps) > 5.0 {
                let crosswindSpeed = abs(powerSeg.averageCrosswindMps) * (settings.units == .metric ? 3.6 : 2.237)
                
                if crosswindSpeed > WindThresholds.veryStrongWind {
                    severityScore += 7.0
                    conditions.append("Dangerous \(Int(crosswindSpeed))\(settings.units.speedUnitAbbreviation) crosswind")
                    strategicNotes.append("⚠️ SAFETY: Reduce speed, avoid sudden movements, deep wheels unstable")
                } else if crosswindSpeed > WindThresholds.significantWind {
                    severityScore += 4.0
                    conditions.append("Strong \(Int(crosswindSpeed))\(settings.units.speedUnitAbbreviation) crosswind")
                    
                    // Crosswinds create partial headwind effect
                    let effectiveHeadwind = calculateEffectiveCrosswindDrag(
                        crosswindSpeed: crosswindSpeed,
                        riderSpeed: powerSeg.calculatedSpeedMps * (settings.units == .metric ? 3.6 : 2.237)
                    )
                    
                    powerAdjustments.append("Crosswind creates ~\(Int(effectiveHeadwind))\(settings.units.speedUnitAbbreviation) drag")
                    strategicNotes.append("Crosswind creates partial headwind effect")
                }
            }
            
            // --- TEMPERATURE IMPACT (ONLY EXTREMES OR LOCAL VARIATIONS) ---
            // Don't flag general cold/hot - that's in strategic guidance
            // Only flag if this segment is significantly different from route average
            let tempDifferenceFromAvg = abs(powerSeg.averageTemperatureC - avgTemp)
            let isLocalExtreme = tempDifferenceFromAvg > (settings.units == .metric ? 5 : 9) // 5°C or 9°F difference
            
            let heatThreshold = settings.units == .metric ? 32.0 : 90.0 // Very hot
            let coldThreshold = settings.units == .metric ? 0.0 : 32.0  // Freezing
            
            if temp > heatThreshold && !routeIsGenerallyHot {
                severityScore += 3.0
                let dehydrationRisk = calculateDehydrationRisk(temp: temp, humidity: humidity)
                
                if dehydrationRisk > 0.7 {
                    conditions.append("Extreme heat: \(Int(temp))\(settings.units.tempSymbol)")
                    strategicNotes.append("🔥 CRITICAL: Increase fluid intake by 50%, reduce power 5-8%")
                    severityScore += 2.0
                }
            } else if temp < coldThreshold && (isLocalExtreme || !routeIsGenerallyCold) {
                // Only flag freezing if it's unusually cold for this route
                severityScore += 2.0
                conditions.append("Below freezing: \(Int(temp))\(settings.units.tempSymbol)")
                strategicNotes.append("❄️ Risk of ice on roads, numb extremities")
            }
            
            // --- HUMIDITY IMPACT (ONLY WITH HEAT) ---
            if humidity > 80 && temp > (settings.units == .metric ? 26 : 79) && !routeIsGenerallyHot {
                severityScore += 2.0
                conditions.append("High humidity (\(humidity)%)")
                strategicNotes.append("💧 Sweat evaporation reduced - increase cooling strategies")
            }
            
            // --- UV EXPOSURE (ONLY VERY HIGH) ---
            if let weatherPoint = findClosestWeatherPoint(to: powerSeg, in: weatherPoints),
               let uvIndex = weatherPoint.weather.uvIndex {
                if uvIndex >= 9 { // Only flag very high UV
                    severityScore += 2.0
                    conditions.append("Very high UV (Index \(Int(uvIndex)))")
                    strategicNotes.append("☀️ Apply sunscreen, consider sun sleeves")
                }
            }
            
            // --- VISIBILITY CONCERNS ---
            if let weatherPoint = findClosestWeatherPoint(to: powerSeg, in: weatherPoints) {
                let hasRain = weatherPoint.weather.pop >= 0.5
                let weatherDesc = weatherPoint.weather.description.lowercased()
                let hasFog = weatherDesc.contains("fog") || weatherDesc.contains("mist")
                
                if hasFog {
                    severityScore += 3.0
                    conditions.append("Poor visibility (fog/mist)")
                    strategicNotes.append("👁️ Reduce speed, use lights, increase following distance")
                }
            }
            
            // --- COMBINED EFFECTS ---
            if windSpeedUserUnits > WindThresholds.significantWind {
                // Wind + extreme temperature
                if temp > heatThreshold {
                    severityScore += 2.0
                    strategicNotes.append("⚠️ Wind + heat = increased dehydration risk")
                } else if temp < coldThreshold && routeIsGenerallyCold {
                    // Calculate wind chill for very cold + windy
                    let windChill = calculateWindChill(temp: temp, windSpeed: windSpeedUserUnits)
                    let windChillExtreme = windChill < (settings.units == .metric ? -10 : 14)
                    
                    if windChillExtreme && !conditions.contains(where: { $0.contains("freezing") }) {
                        severityScore += 3.0
                        conditions.append("Severe wind chill: feels like \(Int(windChill))\(settings.units.tempSymbol)")
                        strategicNotes.append("❄️💨 CRITICAL: Protect all exposed skin, risk of frostbite")
                    }
                }
            }
            
            // Heat + Humidity combination (only if not flagged already)
            if temp > (settings.units == .metric ? 30 : 86) && humidity > 70 && !conditions.contains(where: { $0.contains("heat") }) {
                severityScore += 2.0
                conditions.append("Heat + humidity combination")
                strategicNotes.append("🔥💧 Dangerous combination - monitor for heat exhaustion")
            }
            
            // Only include segments with meaningful weather impact (raised threshold)
            if severityScore >= 5.0 {
                let distanceMarker = formatDistance(powerSeg.startPoint.distance)
                
                let segment = CriticalWeatherSegment(
                    segmentIndex: index,
                    distanceMarker: distanceMarker,
                    weatherConditions: conditions.joined(separator: " • "),
                    powerAdjustment: powerAdjustments.first ?? "",
                    strategicNotes: strategicNotes.joined(separator: " • "),
                    severity: severityScore
                )
                
                segments.append((segment, severityScore))
            }
        }
        
        // Sort by severity and return top 10
        return segments
            .sorted { $0.severity > $1.severity }
            .prefix(10)
            .map { $0.segment }
    }
    
    // MARK: - Strategic Guidance Generation
    
    private func generateStrategicGuidance(powerSegments: [PowerRouteSegment]) -> [StrategicGuidance] {
        var guidance: [StrategicGuidance] = []
        
        // Analyze wind patterns across route
        let windAnalysis = analyzeRouteWindPattern(segments: powerSegments)
        
        // HEADWIND STRATEGY
        if windAnalysis.significantHeadwindDuration > 10 {
            let avgHeadwindSpeed = windAnalysis.avgHeadwindSpeed * (settings.units == .metric ? 3.6 : 2.237)
            let rawPowerBoost = Int(avgHeadwindSpeed / 3.0)
            
            // Check against user's FTP for realistic recommendations
            let userFTP = Double(settings.functionalThresholdPower)
            let avgCurrentPower = powerSegments.reduce(0.0) { $0 + $1.powerRequired } / Double(powerSegments.count)
            let maxSustainablePower = userFTP * 0.95
            let availablePower = max(0, maxSustainablePower - avgCurrentPower)
            
            let recommendedBoost = min(rawPowerBoost, Int(availablePower))
            
            if Double(recommendedBoost) < Double(rawPowerBoost) / 2.0 {
                // Cannot realistically add enough power
                guidance.append(StrategicGuidance(
                    category: .strategy,
                    title: "Headwind Management Strategy",
                    description: "You'll face \(Int(windAnalysis.significantHeadwindDuration)) minutes of significant headwind (\(Int(avgHeadwindSpeed))\(settings.units.speedUnitAbbreviation)). The wind is too strong to fully compensate with power - accept pace reduction to avoid overextension.",
                    actionItems: [
                        "Add up to \(recommendedBoost)W during headwinds (sustainable limit)",
                        "Accept 10-15% speed reduction rather than unsustainable power",
                        "Focus on aerodynamics: get low, reduce frontal area",
                        "Save energy for critical sections like climbs"
                    ],
                    impactLevel: .high
                ))
            } else {
                // Can add meaningful power
                guidance.append(StrategicGuidance(
                    category: .pacing,
                    title: "Headwind Power Strategy",
                    description: "You'll face \(Int(windAnalysis.significantHeadwindDuration)) minutes of significant headwind (\(Int(avgHeadwindSpeed))\(settings.units.speedUnitAbbreviation)). Research shows pushing 10-15% harder into headwinds reduces overall time more than conserving energy.",
                    actionItems: [
                        "Target +\(recommendedBoost)W during strong headwind segments",
                        "This will feel hard but saves time where it counts most",
                        "Plan to recover during tailwind/descent sections",
                        "Monitor RPE - back off if above sustainable effort"
                    ],
                    impactLevel: .high
                ))
            }
        }
        
        // TAILWIND RECOVERY
        if windAnalysis.significantTailwindDuration > 15 {
            guidance.append(StrategicGuidance(
                category: .strategy,
                title: "Strategic Recovery Windows",
                description: "You have \(Int(windAnalysis.significantTailwindDuration)) minutes of helpful tailwinds. Use these segments strategically for recovery and nutrition.",
                actionItems: [
                    "Reduce power by 10-15W during tailwind segments",
                    "Focus on hydration and fueling during these easier sections",
                    "Maintain good position to maximize wind assistance"
                ],
                impactLevel: .medium
            ))
        }
        
        // TEMPERATURE MANAGEMENT
        let tempAnalysis = analyzeTemperatureProfile(powerSegments: powerSegments)
        if tempAnalysis.hasHeatStress {
            let maxTemp = settings.units == .metric ?
                tempAnalysis.maxTemp :
                (tempAnalysis.maxTemp * 9/5 + 32)
            
            guidance.append(StrategicGuidance(
                category: .safety,
                title: "Heat Management Critical",
                description: "Temperatures reach \(Int(maxTemp))°\(settings.units.tempSymbol) during your ride. Heat stress significantly impacts performance and safety.",
                actionItems: [
                    "Pre-cool: Drink 16oz cold fluid 15min before start",
                    "Double hydration rate during hot sections",
                    "Reduce power targets by 5-8% when very hot",
                    "Pour water on head/neck to aid cooling if available"
                ],
                impactLevel: .high
            ))
        }
        
        // PRECIPITATION TIMING
        let precipAnalysis = analyzePrecipitationPattern(powerSegments: powerSegments)
        if precipAnalysis.hasSignificantRain {
            guidance.append(StrategicGuidance(
                category: .safety,
                title: "Rain During Ride",
                description: "Rain is likely during your ride (\(Int(precipAnalysis.maxPrecipChance * 100))% chance). Wet conditions significantly affect bike handling and braking.",
                actionItems: [
                    "Pack waterproof jacket and shoe covers",
                    "Reduce cornering speed by 20-30% in wet conditions",
                    "Increase braking distance by 50%",
                    "Watch for painted lines and metal surfaces - extremely slippery when wet"
                ],
                impactLevel: precipAnalysis.maxPrecipChance > 0.7 ? .critical : .high
            ))
        }
        
        // HUMIDITY & HEAT INDEX
        let humidityAnalysis = analyzeHumidityImpact(powerSegments: powerSegments)
        if humidityAnalysis.hasDangerousHeatIndex {
            guidance.append(StrategicGuidance(
                category: .safety,
                title: "Dangerous Heat Index",
                description: "Heat index reaches \(Int(humidityAnalysis.maxHeatIndex))°F due to high humidity. This severely limits your body's cooling ability.",
                actionItems: [
                    "Consider delaying ride to cooler hours",
                    "Double normal hydration rate (1+ bottle/hour)",
                    "Take 2-minute cooling breaks every 30 minutes",
                    "Watch for heat exhaustion: dizziness, nausea, excessive fatigue"
                ],
                impactLevel: .critical
            ))
        }
        
        // UV PROTECTION
        let uvAnalysis = analyzeUVExposure(powerSegments: powerSegments)
        if uvAnalysis.hasHighUVExposure {
            guidance.append(StrategicGuidance(
                category: .safety,
                title: "High UV Exposure",
                description: "UV index reaches \(Int(uvAnalysis.maxUVIndex)) during your ride. Extended exposure at this level causes skin damage.",
                actionItems: [
                    "Apply SPF 50+ sunscreen before start",
                    "Consider arm sleeves and leg warmers for sun protection",
                    "Reapply sunscreen every 2 hours if ride is long",
                    "Wear UV-blocking sunglasses"
                ],
                impactLevel: uvAnalysis.maxUVIndex >= 10 ? .high : .medium
            ))
        }
        
        // COLD WEATHER STRATEGY
        if tempAnalysis.hasColdStress {
            let minTemp = settings.units == .metric ?
                tempAnalysis.minTemp :
                (tempAnalysis.minTemp * 9/5 + 32)
            
            guidance.append(StrategicGuidance(
                category: .safety,
                title: "Cold Weather Strategy",
                description: "Temperatures drop to \(Int(minTemp))°\(settings.units.tempSymbol). Cold affects breathing efficiency and muscle function.",
                actionItems: [
                    "Layer appropriately: base + insulation + wind shell",
                    "Protect extremities: gloves, toe covers, ear protection",
                    "Expect 3-5% power reduction due to cold",
                    "Warm up gradually - cold muscles are injury-prone"
                ],
                impactLevel: minTemp < (settings.units == .metric ? 0 : 32) ? .high : .medium
            ))
        }
        
        // WIND DIRECTION CHANGES
        if windAnalysis.hasSignificantDirectionChange {
            guidance.append(StrategicGuidance(
                category: .strategy,
                title: "Wind Direction Shift",
                description: "Wind direction changes significantly during your ride. Your pacing strategy should account for this shift.",
                actionItems: [
                    "First section: \(windAnalysis.firstHalfDescription)",
                    "Later section: \(windAnalysis.secondHalfDescription)",
                    "Adjust nutrition timing to match effort distribution"
                ],
                impactLevel: .medium
            ))
        }
        
        return guidance
    }
    
    // MARK: - Overall Recommendation
    
    private func generateOverallRecommendation(powerSegments: [PowerRouteSegment]) -> String {
        var recommendations: [String] = []
        
        // Wind impact analysis
        let totalTime = powerSegments.reduce(0.0) { $0 + $1.timeSeconds }
        let headwindTime = powerSegments.filter { $0.averageHeadwindMps > 3.0 }
            .reduce(0.0) { $0 + $1.timeSeconds }
        let headwindPercent = (headwindTime / totalTime) * 100
        
        if headwindPercent > 40 {
            let avgHeadwind = powerSegments.filter { $0.averageHeadwindMps > 3.0 }
                .map { $0.averageHeadwindMps }
                .reduce(0, +) / Double(powerSegments.filter { $0.averageHeadwindMps > 3.0 }.count)
            let windSpeed = avgHeadwind * (settings.units == .metric ? 3.6 : 2.237)
            
            recommendations.append("⚠️ HEADWIND-DOMINATED ROUTE (\(Int(headwindPercent))% of ride time at \(Int(windSpeed))\(settings.units.speedUnitAbbreviation) average)")
            recommendations.append("Strategy: Push 10-15% harder into wind, recover with tailwind.")
        }
        
        // Temperature extremes
        let temps = powerSegments.map {
            settings.units == .metric ?
                $0.averageTemperatureC :
                ($0.averageTemperatureC * 9/5 + 32)
        }
        if let maxTemp = temps.max(), maxTemp > (settings.units == .metric ? 30 : 86) {
            recommendations.append("🔥 HIGH HEAT STRESS RISK (\(Int(maxTemp))°\(settings.units.tempSymbol) max).")
            recommendations.append("Reduce intensity by 5-8% and increase hydration by 50%.")
        }
        
        // Crosswind safety
        let maxCrosswind = powerSegments.map { abs($0.averageCrosswindMps) }.max() ?? 0
        let crosswindSpeed = maxCrosswind * (settings.units == .metric ? 3.6 : 2.237)
        if crosswindSpeed > WindThresholds.veryStrongWind {
            recommendations.append("⚠️ DANGEROUS CROSSWINDS up to \(Int(crosswindSpeed))\(settings.units.speedUnitAbbreviation).")
            recommendations.append("Reduce speed in exposed sections, deep wheels not recommended.")
        }
        
        return recommendations.joined(separator: " ")
    }
    
    // MARK: - Analysis Helpers
    
    private struct WindAnalysisResult {
        let significantHeadwindDuration: Double
        let significantTailwindDuration: Double
        let avgHeadwindSpeed: Double
        let hasSignificantDirectionChange: Bool
        let firstHalfDescription: String
        let secondHalfDescription: String
    }
    
    private func analyzeRouteWindPattern(segments: [PowerRouteSegment]) -> WindAnalysisResult {
        let totalTime = segments.reduce(0.0) { $0 + $1.timeSeconds }
        let midpoint = totalTime / 2
        
        var headwindTime: Double = 0
        var tailwindTime: Double = 0
        var headwindSum: Double = 0
        var headwindCount: Int = 0
        
        var firstHalfHeadwind: Double = 0
        var secondHalfHeadwind: Double = 0
        var cumTime: Double = 0
        
        for seg in segments {
            let isFirstHalf = cumTime < midpoint
            
            if seg.averageHeadwindMps > 3.0 {
                headwindTime += seg.timeSeconds
                headwindSum += seg.averageHeadwindMps
                headwindCount += 1
                
                if isFirstHalf {
                    firstHalfHeadwind += seg.timeSeconds
                } else {
                    secondHalfHeadwind += seg.timeSeconds
                }
            } else if seg.averageHeadwindMps < -3.0 {
                tailwindTime += seg.timeSeconds
            }
            
            cumTime += seg.timeSeconds
        }
        
        let avgHeadwind = headwindCount > 0 ? headwindSum / Double(headwindCount) : 0
        
        // Determine wind description for each half
        let firstDesc = firstHalfHeadwind > (midpoint * 0.3) ? "Mostly headwinds" : "Mixed/favorable winds"
        let secondDesc = secondHalfHeadwind > (midpoint * 0.3) ? "Mostly headwinds" : "Mixed/favorable winds"
        let hasChange = firstDesc != secondDesc
        
        return WindAnalysisResult(
            significantHeadwindDuration: headwindTime / 60,
            significantTailwindDuration: tailwindTime / 60,
            avgHeadwindSpeed: avgHeadwind,
            hasSignificantDirectionChange: hasChange,
            firstHalfDescription: firstDesc,
            secondHalfDescription: secondDesc
        )
    }
    
    private struct TemperatureAnalysisResult {
        let hasHeatStress: Bool
        let hasColdStress: Bool
        let maxTemp: Double
        let minTemp: Double
    }
    
    private func analyzeTemperatureProfile(powerSegments: [PowerRouteSegment]) -> TemperatureAnalysisResult {
        let temps = powerSegments.map { $0.averageTemperatureC }
        let maxTemp = temps.max() ?? 0
        let minTemp = temps.min() ?? 0
        let heatThreshold = settings.units == .metric ? 30.0 : 30.0
        let coldThreshold = settings.units == .metric ? 5.0 : 5.0
        
        return TemperatureAnalysisResult(
            hasHeatStress: maxTemp > heatThreshold,
            hasColdStress: minTemp < coldThreshold,
            maxTemp: maxTemp,
            minTemp: minTemp
        )
    }
    
    private struct PrecipitationAnalysisResult {
        let hasSignificantRain: Bool
        let maxPrecipChance: Double
    }
    
    private func analyzePrecipitationPattern(powerSegments: [PowerRouteSegment]) -> PrecipitationAnalysisResult {
        var maxPop: Double = 0
        
        for seg in powerSegments {
            if let weatherPoint = findClosestWeatherPoint(to: seg, in: weatherPoints) {
                maxPop = max(maxPop, weatherPoint.weather.pop)
            }
        }
        
        return PrecipitationAnalysisResult(
            hasSignificantRain: maxPop >= 0.4,
            maxPrecipChance: maxPop
        )
    }
    
    private struct HumidityAnalysisResult {
        let hasDangerousHeatIndex: Bool
        let maxHeatIndex: Double
    }
    
    private func analyzeHumidityImpact(powerSegments: [PowerRouteSegment]) -> HumidityAnalysisResult {
        var maxHeatIndex: Double = 0
        
        for seg in powerSegments {
            let tempF = seg.averageTemperatureC * 9/5 + 32
            let humidity = seg.averageHumidity
            
            if tempF >= 80 {
                let hi = -42.379 + 2.04901523 * tempF + 10.14333127 * humidity
                    - 0.22475541 * tempF * humidity
                maxHeatIndex = max(maxHeatIndex, hi)
            }
        }
        
        return HumidityAnalysisResult(
            hasDangerousHeatIndex: maxHeatIndex >= 105,
            maxHeatIndex: maxHeatIndex
        )
    }
    
    private struct UVAnalysisResult {
        let hasHighUVExposure: Bool
        let maxUVIndex: Double
    }
    
    private func analyzeUVExposure(powerSegments: [PowerRouteSegment]) -> UVAnalysisResult {
        var maxUV: Double = 0
        
        for seg in powerSegments {
            if let weatherPoint = findClosestWeatherPoint(to: seg, in: weatherPoints),
               let uvIndex = weatherPoint.weather.uvIndex {
                maxUV = max(maxUV, uvIndex)
            }
        }
        
        return UVAnalysisResult(
            hasHighUVExposure: maxUV >= 6,
            maxUVIndex: maxUV
        )
    }
    
    private func findClosestWeatherPoint(to segment: PowerRouteSegment, in points: [RouteWeatherPoint]) -> RouteWeatherPoint? {
        return points.min { point1, point2 in
            let dist1 = abs(point1.distance - segment.startPoint.distance)
            let dist2 = abs(point2.distance - segment.startPoint.distance)
            return dist1 < dist2
        }
    }
    
    // MARK: - Physics Calculations
    
    private func calculateHeadwindPowerPenalty(headwindSpeed: Double, riderSpeed: Double) -> Double {
        let CdA = 0.32
        let rho = 1.225
        
        let normalWindSpeed = riderSpeed
        let withHeadwind = riderSpeed + headwindSpeed
        
        let normalPower = 0.5 * CdA * rho * pow(normalWindSpeed / (settings.units == .metric ? 3.6 : 2.237), 3)
        let headwindPower = 0.5 * CdA * rho * pow(withHeadwind / (settings.units == .metric ? 3.6 : 2.237), 3)
        
        return max(0, headwindPower - normalPower)
    }
    
    private func calculateTailwindPowerBonus(tailwindSpeed: Double, riderSpeed: Double) -> Double {
        let CdA = 0.32
        let rho = 1.225
        
        let normalWindSpeed = riderSpeed
        let withTailwind = max(0.1, riderSpeed - tailwindSpeed)
        
        let normalPower = 0.5 * CdA * rho * pow(normalWindSpeed / (settings.units == .metric ? 3.6 : 2.237), 3)
        let tailwindPower = 0.5 * CdA * rho * pow(withTailwind / (settings.units == .metric ? 3.6 : 2.237), 3)
        
        return max(0, normalPower - tailwindPower)
    }
    
    private func calculateEffectiveCrosswindDrag(crosswindSpeed: Double, riderSpeed: Double) -> Double {
        let apparentWind = sqrt(pow(riderSpeed, 2) + pow(crosswindSpeed, 2))
        return apparentWind - riderSpeed
    }
    
    private func calculateDehydrationRisk(temp: Double, humidity: Int) -> Double {
        // Convert to Fahrenheit if needed for heat index calculation
        let tempF = settings.units == .metric ? (temp * 9/5 + 32) : temp
        
        let heatIndex = -42.379 + 2.04901523 * tempF + 10.14333127 * Double(humidity)
            - 0.22475541 * tempF * Double(humidity)
        
        if heatIndex > 105 { return 1.0 }
        else if heatIndex > 95 { return 0.8 }
        else if heatIndex > 85 { return 0.5 }
        else { return 0.2 }
    }
    
    private func calculateWindChill(temp: Double, windSpeed: Double) -> Double {
        // Wind chill formula (only valid for temps below 50°F / 10°C)
        let tempF = settings.units == .metric ? (temp * 9/5 + 32) : temp
        let windMph = settings.units == .metric ? (windSpeed * 0.621371) : windSpeed
        
        guard tempF <= 50 && windMph >= 3 else { return temp }
        
        let windChill = 35.74 + (0.6215 * tempF) - (35.75 * pow(windMph, 0.16)) + (0.4275 * tempF * pow(windMph, 0.16))
        
        return settings.units == .metric ? ((windChill - 32) * 5/9) : windChill
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if settings.units == .metric {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return String(format: "%.1f mi", meters / 1609.34)
        }
    }
}

// MARK: - Data Models

struct WeatherPacingInsightResult: Identifiable {
    let id = UUID()
    let criticalSegments: [CriticalWeatherSegment]
    let strategicGuidance: [StrategicGuidance]
    let overallRecommendation: String
}

struct CriticalWeatherSegment: Identifiable {
    let id = UUID()
    let segmentIndex: Int
    let distanceMarker: String
    let weatherConditions: String
    let powerAdjustment: String
    let strategicNotes: String
    let severity: Double
    
    var severityColor: Color {
        if severity >= 8 { return .red }
        else if severity >= 5 { return .orange }
        else { return .yellow }
    }
}

struct StrategicGuidance: Identifiable {
    let id = UUID()
    let category: GuidanceCategory
    let title: String
    let description: String
    let actionItems: [String]
    let impactLevel: ImpactLevel
    
    enum GuidanceCategory {
        case pacing, strategy, safety, nutrition
        
        var icon: String {
            switch self {
            case .pacing: return "speedometer"
            case .strategy: return "brain"
            case .safety: return "exclamationmark.shield"
            case .nutrition: return "drop.fill"
            }
        }
    }
    
    enum ImpactLevel {
        case low, medium, high, critical
        
        var color: Color {
            switch self {
            case .low: return .green
            case .medium: return .yellow
            case .high: return .orange
            case .critical: return .red
            }
        }
    }
}
