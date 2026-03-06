//
// PowerPhysicsEngine.swift
//

import Foundation
import CoreLocation
import Combine

struct PowerPhysicsEngine {
    let settings: AppSettings

    // MARK: - Physics constants
    private let g: Double = 9.80665
    private let defaultAirDensity: Double = 1.225
    private let rollingResistance: Double = 0.004
    let frontalArea: Double = 0.38
    let dragCoefficient: Double = 0.88
    private let drivetrainEfficiency: Double = 0.97

    // MARK: - Core Power Calculation
    
    /// This is the primary function to calculate the power required to maintain a given speed.
    func calculateRequiredPower(
        speedMps: Double,
        elevationGrade: Double,
        headwindSpeedMps: Double,
        crosswindSpeedMps: Double,
        airDensity: Double,
        isWet: Bool
    ) -> Double {
        let totalWeightKg = settings.totalWeightKg
        let crr = isWet ? 0.006 : self.rollingResistance

        // 1. Power to overcome rolling resistance
        let rollingPower = crr * totalWeightKg * g * cos(atan(elevationGrade)) * speedMps

        // 2. Power to overcome air resistance (Aerodynamic Drag)
        // BBS-style: We use the apparent wind speed vector
        // speedMps is the bike's velocity. headwindSpeedMps is the wind component against the rider.
        let v_air_sq = pow(speedMps + headwindSpeedMps, 2) + pow(crosswindSpeedMps, 2)
        
        // Drag force: F = 0.5 * Cd * A * rho * v_air^2
        // We project this force back onto the direction of travel
        // The effective headwind component of the drag force depends on the yaw angle,
        // but for a cycling model, using the relative air velocity squared is the standard approach.
        let airResistanceForce = 0.5 * dragCoefficient * frontalArea * airDensity * v_air_sq
        let airPower = airResistanceForce * speedMps

        // 3. Power to overcome gravity (climbing)
        let climbingPower = totalWeightKg * g * sin(atan(elevationGrade)) * speedMps

        // Total power at the wheels
        let totalPower = rollingPower + airPower + climbingPower
        
        // Return power at the pedals, accounting for drivetrain losses
        return max(0, totalPower / drivetrainEfficiency)
    }

    // MARK: - Air Density Calculation
    
    /// Calculates air density (rho) based on temperature, pressure, and humidity.
    /// Uses the ideal gas law: rho = P / (R * T)
    func calculateAirDensity(
        temperatureC: Double,
        pressureHpa: Double,
        relativeHumidity: Double // 0.0 to 1.0
    ) -> Double {
        let tempK = temperatureC + 273.15
        let pressurePa = pressureHpa * 100.0
        
        // Gas constant for dry air
        let Rd = 287.058
        // Gas constant for water vapor
        let Rv = 461.495
        
        // Vapor pressure of water (Magnus-Tetens formula)
        let saturationVaporPressure = 6.112 * exp((17.67 * temperatureC) / (temperatureC + 243.5)) * 100.0
        let vaporPressure = saturationVaporPressure * relativeHumidity
        let dryAirPressure = pressurePa - vaporPressure
        
        let rho = (dryAirPressure / (Rd * tempK)) + (vaporPressure / (Rv * tempK))
        return rho
    }

    // MARK: - Speed Calculation (Robust Bisection Solver)

    /// Calculates the speed for a given power output using a stable Bisection search.
    func calculateSpeed(
        targetPowerWatts: Double,
        elevationGrade: Double,
        headwindSpeedMps: Double,
        crosswindSpeedMps: Double,
        temperature: Double,
        humidity: Double,
        airDensity: Double,
        isWet: Bool
    ) -> Double {
        var lowSpeed: Double = 0.1   // Very slow
        var highSpeed: Double = 25.0 // ~90 km/h
        let tolerance: Double = 0.5  // Watt tolerance

        let powerAtLow = calculateRequiredPower(speedMps: lowSpeed, elevationGrade: elevationGrade, headwindSpeedMps: headwindSpeedMps, crosswindSpeedMps: crosswindSpeedMps, airDensity: airDensity, isWet: isWet)
        let powerAtHigh = calculateRequiredPower(speedMps: highSpeed, elevationGrade: elevationGrade, headwindSpeedMps: headwindSpeedMps, crosswindSpeedMps: crosswindSpeedMps, airDensity: airDensity, isWet: isWet)

        if (powerAtLow < powerAtHigh) { // Normal case: power increases with speed
            if targetPowerWatts < powerAtLow { return lowSpeed }
            if targetPowerWatts > powerAtHigh { return highSpeed }
        } else { // Inverted case: power decreases with speed (strong tailwind/descent)
            if targetPowerWatts > powerAtLow { return lowSpeed }
            if targetPowerWatts < powerAtHigh { return highSpeed }
        }
        
        for _ in 0..<100 { // 100 iterations is more than enough for high precision
            let midSpeed = (lowSpeed + highSpeed) / 2.0
            if (highSpeed - lowSpeed) < 0.01 { break } // Exit if speed is very precise

            let midPower = calculateRequiredPower(speedMps: midSpeed, elevationGrade: elevationGrade, headwindSpeedMps: headwindSpeedMps, crosswindSpeedMps: crosswindSpeedMps, airDensity: airDensity, isWet: isWet)
            
            if abs(midPower - targetPowerWatts) < tolerance { return midSpeed }
            
            if (powerAtLow < powerAtHigh) { // Normal curve
                if midPower < targetPowerWatts { lowSpeed = midSpeed } else { highSpeed = midSpeed }
            } else { // Inverted curve
                if midPower > targetPowerWatts { lowSpeed = midSpeed } else { highSpeed = midSpeed }
            }
        }
        
        return (lowSpeed + highSpeed) / 2.0
    }

    // MARK: - Wind and Grade Helpers (Unchanged)
    
    func calculateHeadwindComponent(windSpeedMps: Double, windDirectionDegrees: Double, rideDirectionDegrees: Double) -> Double {
        let angleRad = (windDirectionDegrees - rideDirectionDegrees) * .pi / 180.0
        return windSpeedMps * cos(angleRad)
    }

    func calculateCrosswindComponent(windSpeedMps: Double, windDirectionDegrees: Double, rideDirectionDegrees: Double) -> Double {
        let angleRad = (windDirectionDegrees - rideDirectionDegrees) * .pi / 180.0
        return windSpeedMps * sin(angleRad)
    }
    
    func calculateGrade(startElevationM: Double, endElevationM: Double, horizontalDistanceM: Double) -> Double {
        guard horizontalDistanceM > 1.0 else { return 0.0 }
        let grade = (endElevationM - startElevationM) / horizontalDistanceM
        return max(-0.3, min(0.3, grade)) // Clamp to realistic grades
    }
    
    func estimateAverageGrade(totalDistanceM: Double, totalElevationGainM: Double) -> Double {
        guard totalDistanceM > 0 else { return 0.0 }
        return totalElevationGainM / totalDistanceM
    }
}
