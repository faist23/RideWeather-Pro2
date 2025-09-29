//
//  PowerRouteSegment.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 9/13/25.
//


//
//  PowerRouteAnalyticsEngine.swift
//  RideWeather Pro
//
//  Integrates power-based physics calculations with existing route analysis
//

import Foundation
import CoreLocation

// MARK: - Power-Based Route Segment

struct PowerRouteSegment {
    let startPoint: RouteWeatherPoint
    let endPoint: RouteWeatherPoint
    let distanceMeters: Double
    let elevationGrade: Double // as decimal (0.05 = 5%)
    let averageHeadwindMps: Double
    let averageTemperatureC: Double
    let averageHumidity: Double
    let calculatedSpeedMps: Double
    let timeSeconds: Double
    let powerRequired: Double // watts
    let segmentType: SegmentType
    
    enum SegmentType {
        case climb, descent, flat
        
        var description: String {
            switch self {
            case .climb: return "Climb"
            case .descent: return "Descent" 
            case .flat: return "Flat"
            }
        }
        
        var icon: String {
            switch self {
            case .climb: return "arrow.up.right"
            case .descent: return "arrow.down.right"
            case .flat: return "arrow.right"
            }
        }
        
        static func from(grade: Double) -> SegmentType {
            if grade > 0.02 { // > 2%
                return .climb
            } else if grade < -0.02 { // < -2%
                return .descent
            } else {
                return .flat
            }
        }
    }
}

// MARK: - Power Route Analysis Result

struct PowerRouteAnalysisResult {
    let segments: [PowerRouteSegment]
    let totalTimeSeconds: Double
    let averageSpeedMps: Double
    let totalEnergyKilojoules: Double
    let powerDistribution: PowerDistribution
    let comparisonWithTraditional: SpeedComparisonResult
    let terrainBreakdown: TerrainBreakdown
    
    var totalTimeMinutes: Double {
        totalTimeSeconds / 60.0
    }
    
    var averageSpeedUserUnits: Double {
        // Convert m/s to user's preferred units
        return averageSpeedMps * 3.6 // to km/h, will be converted to mph if needed
    }
}

struct PowerDistribution {
    let averagePower: Double
    let normalizedPower: Double // weighted average accounting for power variations
    let timeInZones: PowerZones
    let intensityFactor: Double // NP/FTP ratio
    
    struct PowerZones {
        let zone1Seconds: Double // Active recovery (< 55% FTP)
        let zone2Seconds: Double // Endurance (55-75% FTP) 
        let zone3Seconds: Double // Tempo (75-90% FTP)
        let zone4Seconds: Double // Threshold (90-105% FTP)
        let zone5Seconds: Double // VO2 Max (> 105% FTP)
    }
}

struct SpeedComparisonResult {
    let traditionalTimeMinutes: Double
    let powerBasedTimeMinutes: Double
    let timeDifferenceMinutes: Double
    let significantSegments: [String] // descriptions of segments with major differences
    
    var improvementPercentage: Double {
        if traditionalTimeMinutes > 0 {
            return ((traditionalTimeMinutes - powerBasedTimeMinutes) / traditionalTimeMinutes) * 100
        }
        return 0
    }
}

struct TerrainBreakdown {
    let flatDistanceMeters: Double
    let climbingDistanceMeters: Double
    let descendingDistanceMeters: Double
    let averageClimbGrade: Double
    let averageDescentGrade: Double
    let steepestClimbGrade: Double
    let steepestDescentGrade: Double
}

// MARK: - Power Route Analytics Engine

class PowerRouteAnalyticsEngine {
    private let weatherPoints: [RouteWeatherPoint]
    private let settings: AppSettings
    private let elevationAnalysis: ElevationAnalysis?
    private let physicsEngine: PowerPhysicsEngine
    
    // Configuration
    private let segmentTargetLength: Double = 500.0 // meters per segment
    private let minimumSegmentLength: Double = 100.0 // minimum segment length
    
    init(weatherPoints: [RouteWeatherPoint], 
         settings: AppSettings, 
         elevationAnalysis: ElevationAnalysis?) {
        self.weatherPoints = weatherPoints
        self.settings = settings
        self.elevationAnalysis = elevationAnalysis
        self.physicsEngine = PowerPhysicsEngine(settings: settings)
    }
    
    // MARK: - Main Analysis Method
    
    func analyzePowerBasedRoute() -> PowerRouteAnalysisResult {
        let segments = createPowerSegments()
        let totalTime = segments.reduce(0) { $0 + $1.timeSeconds }
        let totalDistance = segments.reduce(0) { $0 + $1.distanceMeters }
        let averageSpeed = totalDistance / totalTime
        let totalEnergy = calculateTotalEnergyKilojoules(segments: segments)
        let powerDistribution = calculatePowerDistribution(segments: segments)
        let comparison = compareWithTraditionalMethod(segments: segments)
        let terrainBreakdown = calculateTerrainBreakdown(segments: segments)
        
        return PowerRouteAnalysisResult(
            segments: segments,
            totalTimeSeconds: totalTime,
            averageSpeedMps: averageSpeed,
            totalEnergyKilojoules: totalEnergy,
            powerDistribution: powerDistribution,
            comparisonWithTraditional: comparison,
            terrainBreakdown: terrainBreakdown
        )
    }
    
    // MARK: - Segment Creation
    
    private func createPowerSegments() -> [PowerRouteSegment] {
        var segments: [PowerRouteSegment] = []
        var currentDistance: Double = 0
        var segmentStartIndex = 0
        
        for i in 1..<weatherPoints.count {
            let segmentDistance = weatherPoints[i].distance - weatherPoints[segmentStartIndex].distance
            
            // Create segment when we reach target length or at the end
            if segmentDistance >= segmentTargetLength || i == weatherPoints.count - 1 {
                if segmentDistance >= minimumSegmentLength {
                    let segment = createPowerSegment(
                        startIndex: segmentStartIndex,
                        endIndex: i,
                        segmentDistance: segmentDistance
                    )
                    segments.append(segment)
                }
                segmentStartIndex = i
            }
        }
        
        return segments
    }
    
    private func createPowerSegment(startIndex: Int, endIndex: Int, segmentDistance: Double) -> PowerRouteSegment {
        let startPoint = weatherPoints[startIndex]
        let endPoint = weatherPoints[endIndex]
        
        // Calculate elevation grade
        let elevationGrade = calculateElevationGrade(
            startPoint: startPoint,
            endPoint: endPoint,
            distance: segmentDistance
        )
        
        // Calculate average conditions for the segment
        let segmentPoints = Array(weatherPoints[startIndex...endIndex])
        let averageConditions = calculateAverageConditions(points: segmentPoints)
        
        // Calculate headwind component
        let averageHeadwind = calculateAverageHeadwind(
            startPoint: startPoint,
            endPoint: endPoint,
            segmentPoints: segmentPoints
        )
        
        // Get target power for this segment
        let targetPower = settings.targetPowerWatts
        
        // Calculate speed using physics engine
        let calculatedSpeed = physicsEngine.calculateSpeed(
            targetPowerWatts: targetPower,
            elevationGrade: elevationGrade,
            headwindSpeedMps: averageHeadwind,
            temperature: averageConditions.temperature,
            humidity: averageConditions.humidity
        )
        
        // Calculate time for this segment
        let segmentTime = segmentDistance / calculatedSpeed
        
        return PowerRouteSegment(
            startPoint: startPoint,
            endPoint: endPoint,
            distanceMeters: segmentDistance,
            elevationGrade: elevationGrade,
            averageHeadwindMps: averageHeadwind,
            averageTemperatureC: averageConditions.temperature,
            averageHumidity: averageConditions.humidity,
            calculatedSpeedMps: calculatedSpeed,
            timeSeconds: segmentTime,
            powerRequired: targetPower,
            segmentType: PowerRouteSegment.SegmentType.from(grade: elevationGrade)
        )
    }
    
    // MARK: - Helper Calculations
    
    private func calculateElevationGrade(startPoint: RouteWeatherPoint, 
                                       endPoint: RouteWeatherPoint, 
                                       distance: Double) -> Double {
        // Try to use actual elevation data first
        if let elevationAnalysis = elevationAnalysis,
           elevationAnalysis.hasActualData,
           !elevationAnalysis.elevationProfile.isEmpty {
            
            // Find elevation points closest to our segment start and end
            let startElevation = findClosestElevation(distance: startPoint.distance, 
                                                    profile: elevationAnalysis.elevationProfile)
            let endElevation = findClosestElevation(distance: endPoint.distance, 
                                                  profile: elevationAnalysis.elevationProfile)
            
            if let start = startElevation, let end = endElevation, distance > 0 {
                return physicsEngine.calculateGrade(
                    startElevationM: start,
                    endElevationM: end,
                    horizontalDistanceM: distance
                )
            }
        }
        
        // Fallback to estimation based on total route elevation
        if let elevationAnalysis = elevationAnalysis {
            return physicsEngine.estimateAverageGrade(
                totalDistanceM: weatherPoints.last?.distance ?? 1000,
                totalElevationGainM: elevationAnalysis.totalGain
            )
        }
        
        // Final fallback - assume mostly flat with slight variation
        return 0.005 // 0.5% average grade
    }
    
    private func findClosestElevation(distance: Double, profile: [ElevationPoint]) -> Double? {
        let closest = profile.min { point1, point2 in
            abs(point1.distance - distance) < abs(point2.distance - distance)
        }
        return closest?.elevation
    }
    
    private struct AverageConditions {
        let temperature: Double // Celsius
        let humidity: Double // percentage
        let windSpeed: Double
        let windDirection: Double
    }
    
    private func calculateAverageConditions(points: [RouteWeatherPoint]) -> AverageConditions {
        let temperatures = points.map { convertToCelsius($0.weather.temp) }
        let humidities = points.map { Double($0.weather.humidity) }
        let windSpeeds = points.map { convertToMps($0.weather.windSpeed) }
        let windDirections = points.map { Double($0.weather.windDeg) }
        
        return AverageConditions(
            temperature: temperatures.reduce(0, +) / Double(temperatures.count),
            humidity: humidities.reduce(0, +) / Double(humidities.count),
            windSpeed: windSpeeds.reduce(0, +) / Double(windSpeeds.count),
            windDirection: windDirections.reduce(0, +) / Double(windDirections.count)
        )
    }
    
    private func calculateAverageHeadwind(startPoint: RouteWeatherPoint,
                                        endPoint: RouteWeatherPoint,
                                        segmentPoints: [RouteWeatherPoint]) -> Double {
        // Calculate bearing of this segment
        let bearing = calculateBearing(from: startPoint.coordinate, to: endPoint.coordinate)
        
        var headwindSum: Double = 0
        for point in segmentPoints {
            let windSpeedMps = convertToMps(point.weather.windSpeed)
            let windDirectionDegrees = Double(point.weather.windDeg)
            
            let headwindComponent = physicsEngine.calculateHeadwindComponent(
                windSpeedMps: windSpeedMps,
                windDirectionDegrees: windDirectionDegrees,
                rideDirectionDegrees: bearing
            )
            
            headwindSum += headwindComponent
        }
        
        return headwindSum / Double(segmentPoints.count)
    }
    
    private func calculateBearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radiansBearing = atan2(y, x)
        
        return (radiansBearing * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
    
    // MARK: - Analysis Calculations
    
    private func calculateTotalEnergyKilojoules(segments: [PowerRouteSegment]) -> Double {
        let totalEnergyJoules = segments.reduce(0) { sum, segment in
            sum + (segment.powerRequired * segment.timeSeconds)
        }
        return totalEnergyJoules / 1000.0 // Convert to kilojoules
    }
    
    private func calculatePowerDistribution(segments: [PowerRouteSegment]) -> PowerDistribution {
        let totalTime = segments.reduce(0) { $0 + $1.timeSeconds }
        let ftp = Double(settings.functionalThresholdPower)
        
        var zone1Time: Double = 0
        var zone2Time: Double = 0
        var zone3Time: Double = 0
        var zone4Time: Double = 0
        var zone5Time: Double = 0
        var powerSquaredSum: Double = 0
        
        for segment in segments {
            let powerPercent = segment.powerRequired / ftp
            
            // Classify time in zones
            if powerPercent < 0.55 {
                zone1Time += segment.timeSeconds
            } else if powerPercent < 0.75 {
                zone2Time += segment.timeSeconds
            } else if powerPercent < 0.90 {
                zone3Time += segment.timeSeconds
            } else if powerPercent < 1.05 {
                zone4Time += segment.timeSeconds
            } else {
                zone5Time += segment.timeSeconds
            }
            
            // For normalized power calculation (4th root of 30-sec rolling average of power^4)
            // Simplified here as power^4 for each segment
            powerSquaredSum += pow(segment.powerRequired, 4) * segment.timeSeconds
        }
        
        let averagePower = segments.reduce(0) { $0 + ($1.powerRequired * $1.timeSeconds) } / totalTime
        let normalizedPower = pow(powerSquaredSum / totalTime, 0.25)
        let intensityFactor = normalizedPower / ftp
        
        return PowerDistribution(
            averagePower: averagePower,
            normalizedPower: normalizedPower,
            timeInZones: PowerDistribution.PowerZones(
                zone1Seconds: zone1Time,
                zone2Seconds: zone2Time,
                zone3Seconds: zone3Time,
                zone4Seconds: zone4Time,
                zone5Seconds: zone5Time
            ),
            intensityFactor: intensityFactor
        )
    }
    
    private func compareWithTraditionalMethod(segments: [PowerRouteSegment]) -> SpeedComparisonResult {
        let powerBasedTime = segments.reduce(0) { $0 + $1.timeSeconds } / 60.0 // minutes
        
        // Calculate traditional time using fixed average speed
        let totalDistance = segments.reduce(0) { $0 + $1.distanceMeters }
        let traditionalSpeedMps = convertToMps(settings.averageSpeed)
        let traditionalTime = (totalDistance / traditionalSpeedMps) / 60.0 // minutes
        
        // Find segments with significant differences
        var significantSegments: [String] = []
        for segment in segments {
            let traditionalSegmentTime = segment.distanceMeters / traditionalSpeedMps
            let timeDifference = abs(segment.timeSeconds - traditionalSegmentTime)
            
            if timeDifference > 60 { // More than 1 minute difference
                let segmentMiles = segment.distanceMeters / (settings.units == .metric ? 1000 : 1609.34)
                let unit = settings.units == .metric ? "km" : "mi"
                significantSegments.append(
                    "\(segment.segmentType.description) at \(String(format: "%.1f", segmentMiles)) \(unit): \(Int(timeDifference/60)) min difference"
                )
            }
        }
        
        return SpeedComparisonResult(
            traditionalTimeMinutes: traditionalTime,
            powerBasedTimeMinutes: powerBasedTime,
            timeDifferenceMinutes: powerBasedTime - traditionalTime,
            significantSegments: significantSegments
        )
    }
    
    private func calculateTerrainBreakdown(segments: [PowerRouteSegment]) -> TerrainBreakdown {
        var flatDistance: Double = 0
        var climbDistance: Double = 0
        var descentDistance: Double = 0
        var climbGrades: [Double] = []
        var descentGrades: [Double] = []
        
        var steepestClimb: Double = 0
        var steepestDescent: Double = 0
        
        for segment in segments {
            switch segment.segmentType {
            case .flat:
                flatDistance += segment.distanceMeters
            case .climb:
                climbDistance += segment.distanceMeters
                climbGrades.append(segment.elevationGrade)
                steepestClimb = max(steepestClimb, segment.elevationGrade)
            case .descent:
                descentDistance += segment.distanceMeters
                descentGrades.append(abs(segment.elevationGrade))
                steepestDescent = min(steepestDescent, segment.elevationGrade)
            }
        }
        
        return TerrainBreakdown(
            flatDistanceMeters: flatDistance,
            climbingDistanceMeters: climbDistance,
            descendingDistanceMeters: descentDistance,
            averageClimbGrade: climbGrades.isEmpty ? 0 : climbGrades.reduce(0, +) / Double(climbGrades.count),
            averageDescentGrade: descentGrades.isEmpty ? 0 : descentGrades.reduce(0, +) / Double(descentGrades.count),
            steepestClimbGrade: steepestClimb,
            steepestDescentGrade: steepestDescent
        )
    }
    
    // MARK: - Unit Conversion Helpers
    
    private func convertToCelsius(_ temp: Double) -> Double {
        return settings.units == .metric ? temp : (temp - 32) * 5/9
    }
    
    private func convertToMps(_ speed: Double) -> Double {
        return settings.units == .metric ? speed / 3.6 : speed * 0.44704
    }
    
    // MARK: - Public Convenience Methods
    
    /// Get estimated time improvement/degradation compared to simple average speed method
    func getTimeComparisonSummary() -> String {
        let result = analyzePowerBasedRoute()
        let comparison = result.comparisonWithTraditional
        
        let timeDiffMinutes = abs(comparison.timeDifferenceMinutes)
        let hours = Int(timeDiffMinutes) / 60
        let minutes = Int(timeDiffMinutes) % 60
        
        let timeString = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        
        if comparison.timeDifferenceMinutes > 1 {
            return "Power analysis suggests ride will take \(timeString) longer due to terrain and wind conditions"
        } else if comparison.timeDifferenceMinutes < -1 {
            return "Power analysis suggests ride will be \(timeString) faster than average speed estimate"
        } else {
            return "Power analysis closely matches average speed estimate"
        }
    }
    
    /// Get the most challenging segment description
    func getMostChallengingSegment() -> String? {
        let result = analyzePowerBasedRoute()
        let segments = result.segments
        
        // Find segment requiring highest power relative to FTP
        let challengingSegment = segments.max { s1, s2 in
            let s1Intensity = s1.powerRequired / Double(settings.functionalThresholdPower)
            let s2Intensity = s2.powerRequired / Double(settings.functionalThresholdPower)
            return s1Intensity < s2Intensity
        }
        
        guard let segment = challengingSegment else { return nil }
        
        let distanceInUserUnits = segment.distanceMeters / (settings.units == .metric ? 1000 : 1609.34)
        let unit = settings.units == .metric ? "km" : "mi"
        let gradePercent = segment.elevationGrade * 100
        let intensity = (segment.powerRequired / Double(settings.functionalThresholdPower)) * 100
        
        return "Most challenging: \(segment.segmentType.description.lowercased()) at \(String(format: "%.1f", distanceInUserUnits)) \(unit) (\(String(format: "%.1f", gradePercent))% grade, \(Int(intensity))% FTP)"
    }
    
    /// Check if power-based analysis suggests significantly different pacing strategy
    func suggestsPacingAdjustment() -> Bool {
        let result = analyzePowerBasedRoute()
        return !result.comparisonWithTraditional.significantSegments.isEmpty
    }
}