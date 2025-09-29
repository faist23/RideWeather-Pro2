//
// PowerPhysicsEngine.swift - Physics-based speed calculations using FTP
//

import Foundation
import CoreLocation

struct PowerPhysicsEngine {
    let settings: AppSettings
    
    // MARK: - Physics Constants
    private let gravity: Double = 9.81 // m/s²
    private let airDensity: Double = 1.225 // kg/m³ at sea level, 15°C
    private let rollingResistance: Double = 0.004 // typical for road tires on pavement
    
    // Aerodynamics (typical values for road cycling)
    private let frontalArea: Double = 0.4 // m² (rider + bike frontal area)
    private let dragCoefficient: Double = 0.88 // Cd for typical road cycling position
    
    // MARK: - Main Speed Calculation
    
    /// Calculates sustainable speed for a route segment given power, terrain, and conditions
    func calculateSpeed(
        targetPowerWatts: Double,
        elevationGrade: Double, // as decimal (0.05 = 5% grade)
        headwindSpeedMps: Double, // headwind in m/s (positive = headwind, negative = tailwind)
        temperature: Double, // in Celsius
        humidity: Double // as percentage (0-100)
    ) -> Double {
        
        // Adjust air density for temperature and humidity
        let adjustedAirDensity = calculateAirDensity(temperatureC: temperature, humidityPercent: humidity)
        
        // Use Newton's method to solve for speed iteratively
        // We need to solve: targetPower = requiredPower(speed)
        var speed = 8.0 // Initial guess: 8 m/s (~18 mph)
        let tolerance = 0.01 // m/s
        let maxIterations = 20
        
        for _ in 0..<maxIterations {
            let powerAtSpeed = calculateRequiredPower(
                speedMps: speed,
                elevationGrade: elevationGrade,
                headwindSpeedMps: headwindSpeedMps,
                airDensity: adjustedAirDensity
            )
            
            let powerDifference = powerAtSpeed - targetPowerWatts
            
            if abs(powerDifference) < tolerance {
                break
            }
            
            // Calculate derivative (how power changes with speed) for Newton's method
            let derivative = calculatePowerSpeedDerivative(
                speedMps: speed,
                elevationGrade: elevationGrade,
                headwindSpeedMps: headwindSpeedMps,
                airDensity: adjustedAirDensity
            )
            
            // Newton's method update: speed = speed - f(speed)/f'(speed)
            if derivative > 0 {
                speed = speed - powerDifference / derivative
            } else {
                // Fallback if derivative calculation fails
                speed = speed * 0.95
            }
            
            // Keep speed within reasonable bounds
            speed = max(1.0, min(25.0, speed)) // 1-25 m/s (2.2-56 mph)
        }
        
        return speed
    }
    
    // MARK: - Power Calculation Components
    
    private func calculateRequiredPower(
        speedMps: Double,
        elevationGrade: Double,
        headwindSpeedMps: Double,
        airDensity: Double
    ) -> Double {
        
        let totalWeightKg = settings.totalWeightKg
        
        // 1. Rolling Resistance Power
        let rollingPower = rollingResistance * totalWeightKg * gravity * cos(atan(elevationGrade)) * speedMps
        
        // 2. Air Resistance Power
        let relativeWindSpeed = speedMps + headwindSpeedMps // speed relative to air
        let airResistancePower = 0.5 * dragCoefficient * frontalArea * airDensity * pow(relativeWindSpeed, 3)
        
        // 3. Climbing Power
        let climbingPower = totalWeightKg * gravity * sin(atan(elevationGrade)) * speedMps
        
        // 4. Total mechanical power
        let mechanicalPower = rollingPower + airResistancePower + climbingPower
        
        // 5. Account for drivetrain efficiency (typically ~97% for clean chain)
        let drivetrainEfficiency = 0.97
        let totalPower = mechanicalPower / drivetrainEfficiency
        
        return max(0, totalPower) // Power can't be negative
    }
    
    private func calculatePowerSpeedDerivative(
        speedMps: Double,
        elevationGrade: Double,
        headwindSpeedMps: Double,
        airDensity: Double
    ) -> Double {
        
        let totalWeightKg = settings.totalWeightKg
        let relativeWindSpeed = speedMps + headwindSpeedMps
        
        // Derivatives of each power component with respect to speed
        let rollingDerivative = rollingResistance * totalWeightKg * gravity * cos(atan(elevationGrade))
        let airResistanceDerivative = 1.5 * dragCoefficient * frontalArea * airDensity * pow(relativeWindSpeed, 2)
        let climbingDerivative = totalWeightKg * gravity * sin(atan(elevationGrade))
        
        let totalDerivative = (rollingDerivative + airResistanceDerivative + climbingDerivative) / 0.97
        
        return totalDerivative
    }
    
    // MARK: - Environmental Adjustments
    
    private func calculateAirDensity(temperatureC: Double, humidityPercent: Double) -> Double {
        // Simplified air density calculation accounting for temperature and humidity
        let temperatureK = temperatureC + 273.15
        let standardTemperatureK = 288.15 // 15°C
        
        // Temperature effect (air gets less dense when hotter)
        var adjustedDensity = airDensity * (standardTemperatureK / temperatureK)
        
        // Humidity effect (humid air is less dense than dry air)
        let humidityFactor = 1.0 - (humidityPercent / 100.0) * 0.02 // ~2% reduction at 100% humidity
        adjustedDensity *= humidityFactor
        
        return adjustedDensity
    }
    
    // MARK: - Convenience Methods
    
    /// Calculate speed for a flat section with no wind (useful for baseline estimates)
    func baselineSpeed(targetPowerWatts: Double) -> Double {
        return calculateSpeed(
            targetPowerWatts: targetPowerWatts,
            elevationGrade: 0.0,
            headwindSpeedMps: 0.0,
            temperature: 20.0,
            humidity: 50.0
        )
    }
    
    /// Calculate time to complete a distance at calculated speed
    func calculateSegmentTime(
        distanceMeters: Double,
        targetPowerWatts: Double,
        elevationGrade: Double,
        headwindSpeedMps: Double,
        temperature: Double,
        humidity: Double
    ) -> TimeInterval {
        
        let speedMps = calculateSpeed(
            targetPowerWatts: targetPowerWatts,
            elevationGrade: elevationGrade,
            headwindSpeedMps: headwindSpeedMps,
            temperature: temperature,
            humidity: humidity
        )
        
        return distanceMeters / speedMps // seconds
    }
    
    /// Convert wind speed from weather data to headwind component
    func calculateHeadwindComponent(
        windSpeedMps: Double,
        windDirectionDegrees: Double,
        rideDirectionDegrees: Double
    ) -> Double {
        
        // Calculate angle between wind and ride direction
        let windAngleRad = (windDirectionDegrees - rideDirectionDegrees) * .pi / 180.0
        
        // Headwind component (positive = headwind, negative = tailwind)
        let headwindComponent = windSpeedMps * cos(windAngleRad)
        
        return headwindComponent
    }
    
    // MARK: - Grade Calculation from Elevation Data
    
    /// Calculate elevation grade between two points
    func calculateGrade(
        startElevationM: Double,
        endElevationM: Double,
        horizontalDistanceM: Double
    ) -> Double {
        
        guard horizontalDistanceM > 0 else { return 0.0 }
        
        let elevationChange = endElevationM - startElevationM
        let grade = elevationChange / horizontalDistanceM
        
        // Limit to reasonable grades (-30% to +30%)
        return max(-0.3, min(0.3, grade))
    }
    
    /// Estimate grade from distance and total elevation if detailed elevation data isn't available
    func estimateAverageGrade(totalDistanceM: Double, totalElevationGainM: Double) -> Double {
        guard totalDistanceM > 0 else { return 0.0 }
        
        // This is a rough approximation - actual grades will vary significantly
        return totalElevationGainM / totalDistanceM
    }
}