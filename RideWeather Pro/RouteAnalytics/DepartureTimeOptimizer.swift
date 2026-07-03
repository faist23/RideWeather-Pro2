//
//  DepartureTimeOptimizer.swift
//  RideWeather Pro
//

import Foundation
import CoreLocation
import Solar

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
        let routeLocation = routePoints[0]

        // Baseline conditions at the planned start, so candidates can also win on heat relief
        let baseSim = simulateRide(start: baseStartTime, segments: simulationSegments, forecast: hourlyForecast)

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
            let sim = simulateRide(
                start: candidateStart,
                segments: simulationSegments,
                forecast: hourlyForecast
            )

            // 2. Calculate Savings
            let savingsSeconds = baseDuration - sim.duration
            let heatIndexDropF = baseSim.maxHeatIndexF - sim.maxHeatIndexF

            // A candidate qualifies by saving time (> 2 minutes or > 1.5%), or by
            // meaningful heat-index relief when the planned start hits Danger levels
            let savesTime = savingsSeconds > 120 || (savingsSeconds / baseDuration) > 0.015
            let beatsTheHeat = baseSim.maxHeatIndexF >= 103
                && heatIndexDropF >= 10
                && sim.duration <= baseDuration * 1.08

            if savesTime || beatsTheHeat {

                let improvementPct = max(0, Int((savingsSeconds / baseDuration) * 100))
                let benefit: String
                if savesTime {
                    benefit = generateBenefitString(savings: savingsSeconds, avgWind: sim.avgWindVector, maxTemp: sim.maxTemp)
                } else {
                    let drop = settings.units == .metric ? heatIndexDropF * 5 / 9 : heatIndexDropF
                    benefit = "Heat index \(Int(drop.rounded()))\(settings.units.tempSymbol) lower"
                }

                let daylight = evaluateDaylight(start: candidateStart, duration: sim.duration, location: routeLocation)
                let heatCategory = HeatIndexCalculator.Category(heatIndexF: sim.maxHeatIndexF)
                let weatherScore = self.weatherScore(heatCategory: heatCategory)
                let tradeoff = generateTradeoffString(
                    newStart: candidateStart,
                    maxTemp: sim.maxTemp,
                    heatCategory: heatCategory,
                    daylight: daylight
                )

                let physicsScore = min(100.0, 70.0 + Double(improvementPct * 2))
                let overall = physicsScore * 0.5 + weatherScore * 0.25 + daylight.score * 0.25

                let unifiedScore = await MainActor.run {
                    return UnifiedRouteScore(
                        overall: overall,
                        safety: 80,
                        weather: weatherScore,
                        daylight: daylight.score,
                        rating: UnifiedRating.from(score: overall)
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

        // Return top 3 by overall score (time savings, heat, and daylight combined),
        // so a dark 5 AM start no longer outranks a daylight option on speed alone
        return candidates
            .sorted {
                if $0.alternativeScore.overall != $1.alternativeScore.overall {
                    return $0.alternativeScore.overall > $1.alternativeScore.overall
                }
                return $0.improvementPercentage > $1.improvementPercentage
            }
            .prefix(3).map { $0 }
    }
    
    // MARK: - Physics Simulation
    
    private func simulateRide(
        start: Date,
        segments: [SimulationSegment],
        forecast: [HourlyForecast]
    ) -> (duration: TimeInterval, avgWindVector: Double, maxTemp: Double, maxHeatIndexF: Double) {

        var currentTime = start
        var totalSeconds: Double = 0
        var netWindVector: Double = 0
        var maxTemp: Double = -100
        var maxHeatIndexF: Double = -100

        let ftp = Double(settings.functionalThresholdPower)
        let totalWeight = settings.bodyWeight + settings.bikeAndEquipmentWeight

        for segment in segments {
            let weather = findWeather(at: currentTime, in: forecast)
            maxTemp = max(maxTemp, weather.temp)

            let tempF = settings.units == .metric ? weather.temp * 9 / 5 + 32 : weather.temp
            let heatIndexF = HeatIndexCalculator.heatIndexF(temperatureF: tempF, relativeHumidity: Double(weather.humidity))
            maxHeatIndexF = max(maxHeatIndexF, heatIndexF)

            let windSpeedMps = settings.units == .metric ? weather.windSpeed / 3.6 : weather.windSpeed * 0.44704
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

        return (totalSeconds, netWindVector / Double(segments.count), maxTemp, maxHeatIndexF)
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
    
    // MARK: - Daylight & Heat Scoring

    private struct DaylightEvaluation {
        let score: Double
        let startsInDark: Bool
        let finishesAfterSunset: Bool
    }

    /// Scores a candidate window against real sunrise/sunset for the route's
    /// location, so pre-dawn starts stop outranking daylight options on speed alone.
    private func evaluateDaylight(start: Date, duration: TimeInterval, location: CLLocationCoordinate2D) -> DaylightEvaluation {
        guard let solar = Solar(for: start, coordinate: location),
              let sunrise = solar.sunrise,
              let sunset = solar.sunset else {
            return DaylightEvaluation(score: 100, startsInDark: false, finishesAfterSunset: false)
        }

        let rideEnd = start.addingTimeInterval(duration)
        let startsInDark = start < sunrise
        let finishesAfterSunset = rideEnd > sunset

        var score: Double = 100
        if startsInDark { score -= 60 }
        if finishesAfterSunset { score -= 50 }
        return DaylightEvaluation(score: max(0, score), startsInDark: startsInDark, finishesAfterSunset: finishesAfterSunset)
    }

    private func weatherScore(heatCategory: HeatIndexCalculator.Category?) -> Double {
        switch heatCategory {
        case nil: return 85
        case .caution: return 70
        case .extremeCaution: return 55
        case .danger: return 30
        case .extremeDanger: return 10
        }
    }

    private func generateTradeoffString(
        newStart: Date,
        maxTemp: Double,
        heatCategory: HeatIndexCalculator.Category?,
        daylight: DaylightEvaluation
    ) -> String? {
        var tradeoffs: [String] = []

        switch heatCategory {
        case .extremeCaution: tradeoffs.append("High Heat Index")
        case .danger: tradeoffs.append("Dangerous Heat Index")
        case .extremeDanger: tradeoffs.append("Extreme Heat Index")
        case .caution, nil: break
        }

        if daylight.startsInDark {
            tradeoffs.append("Starts in the Dark")
        } else if daylight.finishesAfterSunset {
            tradeoffs.append("Finishes After Sunset")
        }

        // Logic for "Cold" warning if needed (e.g. < 5C or < 40F)
        let coldThreshold: Double = settings.units == .metric ? 5.0 : 41.0
        if maxTemp < coldThreshold {
            tradeoffs.append("Cold Conditions")
        }

        return tradeoffs.isEmpty ? nil : tradeoffs.joined(separator: " · ")
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
