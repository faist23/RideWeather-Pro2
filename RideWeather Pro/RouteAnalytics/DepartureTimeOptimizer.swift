//
//  DepartureTimeOptimizer.swift
//  RideWeather Pro
//

import Foundation
import CoreLocation

actor DepartureTimeOptimizer {
    
    private let settings: AppSettings
    
    init(settings: AppSettings) {
        self.settings = settings
    }
    
    /// Analyzes alternative start times (next 24h) to find faster options
    func findOptimalStartTimes(
        routePoints: [CLLocationCoordinate2D],
        hourlyForecast: [HourlyForecast],
        baseStartTime: Date,
        baseDuration: TimeInterval,
        routeDistanceMeters: Double
    ) async -> [OptimalStartTime] {
        
        guard !routePoints.isEmpty, !hourlyForecast.isEmpty else { return [] }
        
        // FIX: Scan the next 24 hours instead of just 3 hours
        // We check every hour from now until +24h
        var candidates: [OptimalStartTime] = []
        
        // Downsample route for fast simulation
        let simulationSegments = createSimulationSegments(routePoints: routePoints, targetCount: 50)
        
        // Generate offsets for the next 24 hours (in seconds)
        // We start at +1 hour to avoid suggesting "Now"
        let hoursToCheck = 1...24
        
        for hour in hoursToCheck {
            let offset = TimeInterval(hour * 3600)
            let candidateStart = baseStartTime.addingTimeInterval(offset)
            
            // Skip middle of the night (e.g., 11 PM to 4 AM) unless specifically requested
            // This prevents the "3 AM is faster" suggestions for normal users
            let candidateHour = Calendar.current.component(.hour, from: candidateStart)
            if candidateHour >= 23 || candidateHour < 5 {
                continue
            }
            
            // 1. Run Physics Simulation
            let (simDuration, avgWindVector, maxTemp) = simulateRide(
                start: candidateStart,
                segments: simulationSegments,
                forecast: hourlyForecast
            )
            
            // 2. Calculate Savings
            let savingsSeconds = baseDuration - simDuration
            
            // Threshold: Must save > 2 minutes OR > 1.5% of time
            if savingsSeconds > 120 || (savingsSeconds / baseDuration) > 0.015 {
                
                let improvementPct = Int((savingsSeconds / baseDuration) * 100)
                let benefit = generateBenefitString(savings: savingsSeconds, avgWind: avgWindVector, maxTemp: maxTemp)
                
                // FIX: Pass settings to handle units correctly
                let tradeoff = generateTradeoffString(newStart: candidateStart, baseStart: baseStartTime, maxTemp: maxTemp)
                
                let physicsScore = 70.0 + Double(improvementPct * 2)
                
                let unifiedScore = await MainActor.run {
                    return UnifiedRouteScore(
                        overall: physicsScore,
                        safety: 80,
                        weather: 80,
                        daylight: 100,
                        rating: UnifiedRating.from(score: physicsScore)
                    )
                }
                
                let candidate = OptimalStartTime(
                    startTime: candidateStart,
                    improvementPercentage: improvementPct,
                    primaryBenefit: benefit,
                    tradeoff: tradeoff,
                    window: (start: candidateStart.addingTimeInterval(-1800), end: candidateStart.addingTimeInterval(1800)),
                    alternativeScore: unifiedScore
                )
                
                candidates.append(candidate)
            }
        }
        
        // Return top 3 fastest
        return candidates.sorted { $0.improvementPercentage > $1.improvementPercentage }.prefix(3).map { $0 }
    }
    
    // MARK: - Physics Simulation
    
    private func simulateRide(
        start: Date,
        segments: [SimulationSegment],
        forecast: [HourlyForecast]
    ) -> (duration: TimeInterval, avgWindVector: Double, maxTemp: Double) {
        
        var currentTime = start
        var totalSeconds: Double = 0
        var netWindVector: Double = 0
        var maxTemp: Double = -100
        
        let ftp = Double(settings.functionalThresholdPower)
        let totalWeight = settings.bodyWeight + settings.bikeAndEquipmentWeight
        
        for segment in segments {
            let weather = findWeather(at: currentTime, in: forecast)
            maxTemp = max(maxTemp, weather.temp)
            
            let windSpeedMps = weather.windSpeed * 0.44704
            let windDir = Double(weather.windDeg)
            let rideBearing = segment.bearing
            
            let windAngle = abs(windDir - rideBearing)
            let effectiveWind = windSpeedMps * cos(windAngle * .pi / 180)
            netWindVector += effectiveWind
            
            let power = ftp * 0.75
            let speedMps = solveSpeed(power: power, windSpeed: effectiveWind, weight: totalWeight)
            let segDuration = segment.distance / speedMps
            
            totalSeconds += segDuration
            currentTime = currentTime.addingTimeInterval(segDuration)
        }
        
        return (totalSeconds, netWindVector / Double(segments.count), maxTemp)
    }
    
    private func solveSpeed(power: Double, windSpeed: Double, weight: Double) -> Double {
        var v: Double = 8.0
        for _ in 0..<3 {
            let airVelocity = v + windSpeed
            let drag = 0.5 * 1.225 * 0.35 * (airVelocity * abs(airVelocity))
            let roll = 0.004 * weight * 9.81
            let force = drag + roll
            if force <= 0.1 { break }
            let newV = power / force
            v = (v + newV) / 2
        }
        return max(1.0, v)
    }
    
    private func findWeather(at date: Date, in forecast: [HourlyForecast]) -> HourlyForecast {
        let target = date.timeIntervalSince1970
        return forecast.min(by: { abs($0.date.timeIntervalSince1970 - target) < abs($1.date.timeIntervalSince1970 - target) }) ?? forecast[0]
    }
    
    private func generateBenefitString(savings: TimeInterval, avgWind: Double, maxTemp: Double) -> String {
        let minutes = Int(savings / 60)
        if avgWind < -2.0 {
            return "Saves \(minutes) min (Tailwind Assist)"
        } else if avgWind < 2.0 {
            return "Saves \(minutes) min (Calmer Winds)"
        } else {
            return "Saves \(minutes) min (Faster Conditions)"
        }
    }
    
    private func generateTradeoffString(newStart: Date, baseStart: Date, maxTemp: Double) -> String? {
        // FIX: Unit-aware Heat Logic
        let heatThreshold: Double = settings.units == .metric ? 30.0 : 86.0
        
        if maxTemp > heatThreshold {
            return "High Heat Risk"
        }
        
        // Logic for "Cold" warning if needed (e.g. < 5C or < 40F)
        let coldThreshold: Double = settings.units == .metric ? 5.0 : 41.0
        if maxTemp < coldThreshold {
            return "Cold Conditions"
        }
        
        let hour = Calendar.current.component(.hour, from: newStart)
        if hour < 6 { return "Very Early Start" }
        // Removed sunset risk check here as 24h search makes it complex;
        // relying on DaylightAnalysis in other views for that.
        
        return nil
    }
    
    // MARK: - Helpers
    
    struct SimulationSegment {
        let distance: Double
        let bearing: Double
    }
    
    private func createSimulationSegments(routePoints: [CLLocationCoordinate2D], targetCount: Int) -> [SimulationSegment] {
        guard routePoints.count > 1 else { return [] }
        let step = max(1, routePoints.count / targetCount)
        var segments: [SimulationSegment] = []
        
        for i in stride(from: 0, to: routePoints.count - step, by: step) {
            let p1 = routePoints[i]
            let p2 = routePoints[i+step]
            let loc1 = CLLocation(latitude: p1.latitude, longitude: p1.longitude)
            let loc2 = CLLocation(latitude: p2.latitude, longitude: p2.longitude)
            let dist = loc2.distance(from: loc1)
            let bearing = getBearing(from: p1, to: p2)
            segments.append(SimulationSegment(distance: dist, bearing: bearing))
        }
        return segments
    }
    
    private func getBearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let rads = atan2(y, x)
        return (rads * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}
