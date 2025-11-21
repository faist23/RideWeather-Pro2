//
//  CombinedRouteAnalytics.swift
//  RideWeather Pro
//
//  Unified analytics combining safety and weather insights
//

import SwiftUI
import CoreLocation

// MARK: - Data Models for Smart Comparison

struct WeatherFeel {
    let label: String
    let icon: String
}

struct WindSummary {
    let headwindPercentage: Double
    let crosswindPercentage: Double
    let tailwindPercentage: Double
}

struct StartTimeComparison {
    let alternativeTime: Date
    let currentScore: UnifiedRouteScore
    let alternativeScore: UnifiedRouteScore
    let currentDaylight: DaylightAnalysis
    let alternativeDaylight: DaylightAnalysis
    let currentWind: WindSummary
    let alternativeWind: WindSummary
    let currentTemps: (min: Double, max: Double)
    let alternativeTemps: (min: Double, max: Double)
    let currentPop: Double
    let alternativePop: Double
    
    // Enhanced comparison metrics
    let currentAvgTemp: Double
    let alternativeAvgTemp: Double
    let currentMaxWind: Double
    let alternativeMaxWind: Double
    let temperatureImprovement: Double
    let windImprovement: Double
    let rainImprovementPercentage: Double
}


// MARK: - Unified Analytics Engine

struct UnifiedRouteAnalyticsEngine {
    let weatherPoints: [RouteWeatherPoint]
    let rideStartTime: Date
    let averageSpeed: Double
    let settings: AppSettings
    let location: CLLocationCoordinate2D
    let elevationAnalysis: ElevationAnalysis?

    // NEW: Store hourly forecast data for better time-based analysis
    private var cachedHourlyForecasts: [HourlyForecast] = []
    
    var safetyEngine: SafetyAnalyticsEngine {
        SafetyAnalyticsEngine(
            weatherPoints: weatherPoints,
            rideStartTime: rideStartTime,
            averageSpeed: averageSpeed,
            units: settings.units,
            location: location
        )
    }
    
    private struct WindThresholds {
        static let minMeaningfulWindSpeed: Double = 8.0
        static let significantWindImprovement: Double = 6.0
        static let strongWindThreshold: Double = 15.0
        static let veryStrongWindThreshold: Double = 25.0
    }

    private enum WindChangeType {
        case improvement, degradation, negligible
    }

    private enum WindChangeMagnitude {
        case low, moderate, high
    }

    private var enhancedInsights: EnhancedRouteInsights {
        EnhancedRouteInsights(
            weatherPoints: weatherPoints,
            rideStartTime: rideStartTime,
            averageSpeed: averageSpeed,
            units: settings.units
        )
    }

    // NEW: Initializer that accepts hourly forecast data
    init(weatherPoints: [RouteWeatherPoint],
         rideStartTime: Date,
         averageSpeed: Double,
         settings: AppSettings,
         location: CLLocationCoordinate2D,
         hourlyForecasts: [HourlyForecast] = [],
         elevationAnalysis: ElevationAnalysis?) { // <-- Add parameter
        self.weatherPoints = weatherPoints
        self.rideStartTime = rideStartTime
        self.averageSpeed = averageSpeed
        self.settings = settings
        self.location = location
        self.cachedHourlyForecasts = hourlyForecasts
        self.elevationAnalysis = elevationAnalysis // <-- Assign property
    }
    
    // MARK: - At-a-Glance Metrics
    
    var weatherFeel: WeatherFeel {
        guard !weatherPoints.isEmpty else { return WeatherFeel(label: "Not Available", icon: "questionmark.circle") }
        
        let avgTemp = weatherPoints.map { $0.weather.temp }.reduce(0, +) / Double(weatherPoints.count)
        let maxWind = weatherPoints.map { $0.weather.windSpeed }.max() ?? 0
        let maxPop = weatherPoints.map { $0.weather.pop }.max() ?? 0
        
        if maxPop >= 0.5 {
            return WeatherFeel(label: "Rain Likely", icon: "cloud.rain.fill")
        }
        if maxWind > (settings.units == .metric ? 25 : 15) {
            return WeatherFeel(label: "Windy Conditions", icon: "wind")
        }
        
        let tempThresholds = settings.units == .metric ? (hot: 29.0, warm: 21.0, cool: 13.0) : (hot: 84.0, warm: 70.0, cool: 55.0)
        
        if avgTemp >= tempThresholds.hot {
            return WeatherFeel(label: "Hot & Humid", icon: "sun.max.fill")
        } else if avgTemp >= tempThresholds.warm {
            return WeatherFeel(label: "Warm & Pleasant", icon: "sun.and.horizon.fill")
        } else if avgTemp >= tempThresholds.cool {
            return WeatherFeel(label: "Cool & Crisp", icon: "leaf.fill")
        } else {
            return WeatherFeel(label: "Cold Ride", icon: "snowflake")
        }
    }
    
    var windSummary: WindSummary {
        guard weatherPoints.count > 1 else {
            return WindSummary(headwindPercentage: 0, crosswindPercentage: 100, tailwindPercentage: 0)
        }
        
        var headwindDistance: Double = 0
        var crosswindDistance: Double = 0
        var tailwindDistance: Double = 0
        
        for i in 0..<(weatherPoints.count - 1) {
            let p1 = weatherPoints[i]
            let p2 = weatherPoints[i + 1]
            
            let segmentDistance = p2.distance - p1.distance
            let bearing = calculateBearing(from: p1.coordinate, to: p2.coordinate)
            
            let windDirection = Double(p1.weather.windDeg)
            
            var angleDifference = abs(bearing - windDirection)
            if angleDifference > 180 {
                angleDifference = 360 - angleDifference
            }
            
            if angleDifference <= 45 {
                headwindDistance += segmentDistance
            } else if angleDifference >= 135 {
                tailwindDistance += segmentDistance
            } else {
                crosswindDistance += segmentDistance
            }
        }
        
        let totalDistance = weatherPoints.last?.distance ?? 1.0
        
        return WindSummary(
            headwindPercentage: (headwindDistance / totalDistance) * 100,
            crosswindPercentage: (crosswindDistance / totalDistance) * 100,
            tailwindPercentage: (tailwindDistance / totalDistance) * 100
        )
    }
    
    private func calculateBearing(from p1: CLLocationCoordinate2D, to p2: CLLocationCoordinate2D) -> Double {
        let lat1 = p1.latitude * .pi / 180
        let lon1 = p1.longitude * .pi / 180
        let lat2 = p2.latitude * .pi / 180
        let lon2 = p2.longitude * .pi / 180
        
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radiansBearing = atan2(y, x)
        
        return (radiansBearing * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
    
    // MARK: - Combined Analytics
    
    var comprehensiveAnalysis: ComprehensiveRouteAnalysis {
        let safetyAnalysis = safetyEngine.combinedSafetyScore
        let daylightAnalysis = safetyEngine.daylightAnalysis
        let weatherSafety = safetyEngine.weatherSafetyAnalysis
        let criticalInsights = enhancedInsights.criticalInsights
        let segments = enhancedInsights.detailedSegments

        // Run the power analysis if the settings are configured for it
        var powerResult: PowerRouteAnalysisResult? = nil
        if settings.speedCalculationMethod == .powerBased && settings.functionalThresholdPower > 0 {
            let powerEngine = PowerRouteAnalyticsEngine(
                weatherPoints: weatherPoints,
                settings: settings,
                elevationAnalysis: nil // Pass your ElevationAnalysis object here if you have it
            )
            powerResult = powerEngine.analyzePowerBasedRoute()
        }

        return ComprehensiveRouteAnalysis(
            overallScore: calculateOverallScore(),
            safetyScore: safetyAnalysis,
            daylightAnalysis: daylightAnalysis,
            weatherSafety: weatherSafety,
            criticalInsights: criticalInsights,
            routeSegments: segments,
            unifiedRecommendations: generateUnifiedRecommendations(),
            betterStartTimes: findOptimalStartTimes(),
            weatherFeel: weatherFeel,
            windSummary: windSummary,
            powerAnalysis: powerResult,
            weatherPoints: self.weatherPoints,
            settings: self.settings,
            elevationAnalysis: self.elevationAnalysis
        )
    }

    private func isWindChangeSignificant(
        currentMaxWind: Double,
        alternativeMaxWind: Double,
        currentWindSummary: WindSummary,
        alternativeWindSummary: WindSummary
    ) -> (isSignificant: Bool, type: WindChangeType, magnitude: WindChangeMagnitude) {
        
        let windImprovement = currentMaxWind - alternativeMaxWind
        let absWindChange = abs(windImprovement)
        
        // If both wind speeds are low, changes aren't meaningful
        if max(currentMaxWind, alternativeMaxWind) < WindThresholds.minMeaningfulWindSpeed {
            return (false, .negligible, .low)
        }
        
        // Determine change type and magnitude
        let changeType: WindChangeType
        let changeMagnitude: WindChangeMagnitude
        
        if absWindChange < WindThresholds.significantWindImprovement {
            changeType = .negligible
            changeMagnitude = .low
        } else if windImprovement > 0 {
            changeType = .improvement
            changeMagnitude = absWindChange > WindThresholds.significantWindImprovement * 1.5 ? .high : .moderate
        } else {
            changeType = .degradation
            changeMagnitude = absWindChange > WindThresholds.significantWindImprovement * 1.5 ? .high : .moderate
        }
        
        // Check if the change crosses meaningful thresholds
        let crossesThreshold =
            (currentMaxWind >= WindThresholds.strongWindThreshold && alternativeMaxWind < WindThresholds.strongWindThreshold) ||
            (currentMaxWind < WindThresholds.strongWindThreshold && alternativeMaxWind >= WindThresholds.strongWindThreshold) ||
            (currentMaxWind >= WindThresholds.veryStrongWindThreshold && alternativeMaxWind < WindThresholds.veryStrongWindThreshold) ||
            (currentMaxWind < WindThresholds.veryStrongWindThreshold && alternativeMaxWind >= WindThresholds.veryStrongWindThreshold)
        
        let isSignificant = changeType != .negligible && (changeMagnitude == .high || crossesThreshold)
        
        return (isSignificant, changeType, changeMagnitude)
    }


    // MARK: - Dynamic Scoring Logic
    func calculateOverallScore() -> UnifiedRouteScore {
        let safetyScore = safetyEngine.combinedSafetyScore.score
        let weatherScore = calculateWeatherComfortScore()
        let daylightScore = calculateDaylightScore()
        
        // Dynamic Weighting Logic - SIMPLIFIED
        var weatherWeight = 0.40
        var daylightWeight = 0.20
        let safetyWeight = 0.40
        
        // If the user's goal is enjoyment, prioritize temperature comfort
        if settings.primaryRidingGoal == .enjoyment && settings.temperatureTolerance != .veryTolerant && settings.temperatureTolerance != .prefersCool {
            weatherWeight = 0.50
            daylightWeight = 0.10
        }
        
        // If the user is focused on performance, they may care less about comfort
        if settings.primaryRidingGoal == .performance {
            weatherWeight = 0.30
            daylightWeight = 0.30
        }
        
        let overallScore = (safetyScore * safetyWeight) + (weatherScore * weatherWeight) + (daylightScore * daylightWeight)
        
        return UnifiedRouteScore(
            overall: overallScore,
            safety: safetyScore,
            weather: weatherScore,
            daylight: daylightScore,
            rating: UnifiedRating.from(score: overallScore)
        )
    }
    
    private func calculateWeatherComfortScore() -> Double {
        guard !weatherPoints.isEmpty else { return 0 }
        
        var totalScore = 0.0
        let idealTemp = settings.idealTemperature
        
        let windPenaltyMultiplier: Double
        switch settings.windTolerance {
        case .windSensitive: windPenaltyMultiplier = 2.5
        case .moderate: windPenaltyMultiplier = 1.7
        case .windTolerant: windPenaltyMultiplier = 1.0
        }
        
        for point in weatherPoints {
            var pointScore = 100.0
            let temp = point.weather.temp
            let tempDiff = abs(temp - idealTemp)
            
            // --- ✅ NEW: DEAL-BREAKER PENALTY ---
            // If the temperature is drastically off, apply a large, immediate penalty.
            // This is the "25 degrees is just too cold" rule.
            let tempThreshold = settings.units == .metric ? 11.0 : 20.0 // 20°F or 11°C
            if tempDiff > tempThreshold {
                pointScore -= 35 // A massive, flat penalty for being unacceptable.
            }
            
            // --- Adjusted Linear Penalty ---
            // The existing penalty is still applied on top of the deal-breaker.
            var tempPenalty: Double = 0
            let signedTempDiff = temp - idealTemp
            
            if signedTempDiff > 0 { // It's HOTTER than ideal
                switch settings.temperatureTolerance {
                case .verySensitive, .prefersWarm: tempPenalty = signedTempDiff * 2.0
                case .neutral: tempPenalty = signedTempDiff * 1.5
                case .prefersCool, .veryTolerant: tempPenalty = signedTempDiff * 1.0
                }
            } else if signedTempDiff < 0 { // It's COLDER than ideal
                switch settings.temperatureTolerance {
                case .verySensitive, .prefersWarm: tempPenalty = abs(signedTempDiff) * 1.5
                case .neutral: tempPenalty = abs(signedTempDiff) * 1.2
                case .prefersCool, .veryTolerant: tempPenalty = abs(signedTempDiff) * 0.8
                }
            }
            
            // Apply all penalties
            pointScore -= tempPenalty
            pointScore -= point.weather.windSpeed * windPenaltyMultiplier
            
            let popPenalty = (point.weather.pop * 100) * 0.5
            pointScore -= popPenalty
            
            let humidityComfortPenalty = max(0, Double(point.weather.humidity - 80) * 0.5)
            pointScore -= humidityComfortPenalty
            
            totalScore += max(0, pointScore)
            
        }
        
        return totalScore / Double(weatherPoints.count)
    }
    
    private func calculateDaylightScore() -> Double {
        let analysis = safetyEngine.daylightAnalysis
        let totalDistance = enhancedInsights.totalDistance
        
        guard totalDistance > 0 else { return 100 }
        
        let darkPercentage = analysis.totalDarkDistance / totalDistance
        let goldenHourDistance = analysis.goldenHourSegments.reduce(0) { $0 + $1.distance }
        let goldenPercentage = goldenHourDistance / totalDistance
        
        var score = 100.0
        score -= darkPercentage * 80
        score += goldenPercentage * 20
        
        return max(0, min(100, score))
    }
    
    // MARK: - Unified Recommendations
    func generateUnifiedRecommendations() -> [UnifiedRecommendation] {
        var recs: [UnifiedRecommendation] = []
        
        // MARK: - NEW: Giblet Freeze Warning Logic
        if settings.enableColdWeatherWarning {
            // Find the lowest temperature forecast during the ride
            if let minTemp = weatherPoints.map({ $0.weather.temp }).min() {
                
                if minTemp <= settings.coldWeatherWarningThreshold {
                    let warningMessage = "Temperatures may drop below your threshold of \(Int(settings.coldWeatherWarningThreshold))\(settings.units.tempSymbol). Consider wind-proof layers for sensitive areas."

                    recs.append(
                        UnifiedRecommendation(
                            title: "Giblet Freeze Warning",
                            message: warningMessage,
                            icon: "snowflake", // A fitting system icon
                            priority: .critical     // Make it a top-level safety warning
                        )
                    )
                }
            }
        }
        
        for insight in enhancedInsights.criticalInsights {
            recs.append(
                UnifiedRecommendation(
                    title: insight.title,
                    message: insight.recommendation,
                    icon: insight.icon,
                    priority: {
                        switch insight.priority {
                        case .critical: return .critical
                        case .important: return .important
                        case .moderate: return .moderate
                        }
                    }()
                )
            )
        }
        
        let temps = weatherPoints.map { $0.weather.temp }
        if let min = temps.min(), let max = temps.max(), max - min > (settings.units == .metric ? 8 : 15) {
            recs.append(
                UnifiedRecommendation(
                    title: "Layer Up",
                    message: "Expect a swing of \(Int(max - min))\(settings.units.tempSymbol) during your ride.",
                    icon: "thermometer.variable",
                    priority: .important
                )
            )
        }
        
        if let maxPop = weatherPoints.map({ $0.weather.pop }).max(), maxPop >= 0.4 {
            recs.append(
                UnifiedRecommendation(
                    title: "Pack Rain Gear",
                    message: "There is up to a \(Int(maxPop * 100))% chance of rain during your ride. Consider a waterproof shell.",
                    icon: "cloud.rain.fill",
                    priority: maxPop >= 0.7 ? .critical : .important
                )
            )
        }
        
        recs.append(contentsOf: generateWindRecommendations())
        
        if safetyEngine.daylightAnalysis.totalDarkDistance > 0 {
            recs.append(
                UnifiedRecommendation(
                    title: "Bring Lights",
                    message: "Parts of your ride will be in darkness – front & rear lights recommended.",
                    icon: "lightbulb",
                    priority: .important
                )
            )
        }
        
        if let maxTemp = temps.max(), maxTemp > (settings.units == .metric ? 28 : 82) {
            recs.append(
                UnifiedRecommendation(
                    title: "Stay Hydrated",
                    message: "High temps (\(Int(maxTemp))\(settings.units.tempSymbol)) expected – carry extra fluids & electrolytes.",
                    icon: "drop.fill",
                    priority: .moderate
                )
            )
        }
        
        return recs
    }
    
    private func generateWindRecommendations() -> [UnifiedRecommendation] {
        // Fix: Add safety check for empty/single point arrays to prevent crashes on route clear
        guard weatherPoints.count > 1 else { return [] }
        
        var recs: [UnifiedRecommendation] = []
        
        var strongestHeadwindPoint: RouteWeatherPoint?
        var strongestHeadwindSpeed: Double = 0
        var strongestCrosswindPoint: RouteWeatherPoint?
        var strongestCrosswindSpeed: Double = 0
        var strongestTailwindPoint: RouteWeatherPoint?
        var strongestTailwindSpeed: Double = 0
        
        for i in 0..<(weatherPoints.count - 1) {
            let p1 = weatherPoints[i]
            let p2 = weatherPoints[i + 1]
            
            let bearing = calculateBearing(from: p1.coordinate, to: p2.coordinate)
            let windDirection = Double(p1.weather.windDeg)
            
            var angleDifference = abs(bearing - windDirection)
            if angleDifference > 180 { angleDifference = 360 - angleDifference }
            
            if angleDifference <= 45 {
                if p1.weather.windSpeed > strongestHeadwindSpeed {
                    strongestHeadwindSpeed = p1.weather.windSpeed
                    strongestHeadwindPoint = p1
                }
            }
            else if angleDifference > 45 && angleDifference < 135 {
                if p1.weather.windSpeed > strongestCrosswindSpeed {
                    strongestCrosswindSpeed = p1.weather.windSpeed
                    strongestCrosswindPoint = p1
                }
            }
            else if angleDifference >= 135 {
                if p1.weather.windSpeed > strongestTailwindSpeed {
                    strongestTailwindSpeed = p1.weather.windSpeed
                    strongestTailwindPoint = p1
                }
            }
        }
        
        // Only generate headwind recommendations if wind is above meaningful threshold
        if let headwindPoint = strongestHeadwindPoint,
           strongestHeadwindSpeed > WindThresholds.strongWindThreshold {
            let mile = settings.units == .metric ? headwindPoint.distance / 1000 : headwindPoint.distance / 1609.34
            recs.append(
                UnifiedRecommendation(
                    title: "Headwinds Ahead",
                    message: "Strongest headwinds expected after mile \(String(format: "%.1f", mile)). Save energy early.",
                    icon: "wind",
                    priority: strongestHeadwindSpeed > WindThresholds.veryStrongWindThreshold ? .critical : .important
                )
            )
        }
        
        // Only generate crosswind recommendations if wind is above meaningful threshold
        if let crosswindPoint = strongestCrosswindPoint,
           strongestCrosswindSpeed > WindThresholds.strongWindThreshold {
            let mile = settings.units == .metric ? crosswindPoint.distance / 1000 : crosswindPoint.distance / 1609.34
            recs.append(
                UnifiedRecommendation(
                    title: "Crosswinds Ahead",
                    message: "Strong crosswinds expected after mile \(String(format: "%.1f", mile)). Be cautious on exposed sections.",
                    icon: "arrow.left.and.right.circle.fill",
                    priority: strongestCrosswindSpeed > WindThresholds.veryStrongWindThreshold ? .important : .moderate
                )
            )
        }
        
        // Only generate tailwind recommendations if wind is above meaningful threshold AND percentage is significant
        if windSummary.tailwindPercentage > 30 &&
           strongestTailwindSpeed > WindThresholds.minMeaningfulWindSpeed {
            if let tailwindPoint = strongestTailwindPoint {
                let mile = settings.units == .metric ? tailwindPoint.distance / 1000 : tailwindPoint.distance / 1609.34
                recs.append(
                    UnifiedRecommendation(
                        title: "Tailwind Boost",
                        message: "Strongest tailwinds around mile \(String(format: "%.1f", mile)). Enjoy the push!",
                        icon: "arrow.down.circle.fill",
                        priority: .low
                    )
                )
            } else {
                recs.append(
                    UnifiedRecommendation(
                        title: "Tailwind Boost",
                        message: "You'll enjoy helpful tailwinds for about \(Int(windSummary.tailwindPercentage))% of your ride.",
                        icon: "arrow.down.circle.fill",
                        priority: .moderate
                    )
                )
            }
        }
        
        return recs
    }

    // MARK: - Smart Start Time Analysis
    
    func findOptimalStartTimes() -> [OptimalStartTime] {
        var alternatives: [OptimalStartTime] = []
        let currentScore = self.calculateOverallScore()
        
        // Date formatter for clean printing
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        
        for hourOffset in -4...20 {
            let alternativeStart = self.rideStartTime.addingTimeInterval(Double(hourOffset) * 3600)
            guard alternativeStart > Date() else { continue }
            
            let alternativeHour = Calendar.current.component(.hour, from: alternativeStart)
            if !isValid(hour: alternativeHour, for: settings.wakeUpEarliness) {
                continue
            }
            
            let alternativeWeatherPoints = generateWeatherPoints(for: alternativeStart)
            let alternativeEngine = UnifiedRouteAnalyticsEngine(
                weatherPoints: alternativeWeatherPoints,
                rideStartTime: alternativeStart,
                averageSpeed: self.averageSpeed,
                settings: self.settings,
                location: self.location,
                hourlyForecasts: self.cachedHourlyForecasts,
                elevationAnalysis: self.elevationAnalysis
            )
            
            let alternativeScore = alternativeEngine.calculateOverallScore()
            
            // --- ✅ ADD THIS DEBUG BLOCK ---
#if DEBUG
            let timeString = timeFormatter.string(from: alternativeStart)
            let overall = String(format: "%.1f", alternativeScore.overall)
            let weather = String(format: "%.1f", alternativeScore.weather)
            let daylight = String(format: "%.1f", alternativeScore.daylight)
            let safety = String(format: "%.1f", alternativeScore.safety)
            
            print("[\(timeString)] Score: \(overall) (Weather: \(weather), Daylight: \(daylight), Safety: \(safety))")
#endif
            // --- END OF DEBUG BLOCK ---
            
            if alternativeScore.overall > currentScore.overall + 5 {
                let improvement = max(0, Int(((alternativeScore.overall - currentScore.overall) / currentScore.overall) * 100))
                let comparison = createDetailedComparison(
                    alternativeTime: alternativeStart,
                    currentScore: currentScore,
                    alternativeScore: alternativeScore,
                    alternativeEngine: alternativeEngine
                )
                let benefit = generatePersonalizedBenefit(for: comparison)
                let tradeoff = generateSmartTradeoff(for: comparison)
                
                alternatives.append(
                    OptimalStartTime(
                        startTime: alternativeStart,
                        improvementPercentage: improvement,
                        primaryBenefit: benefit,
                        tradeoff: tradeoff,
                        window: (start: alternativeStart.addingTimeInterval(-1800), end: alternativeStart.addingTimeInterval(1800)),
                        alternativeScore: alternativeScore // Pass the score object here
                    )
                )
            }
        }
        
        let sortedResults = alternatives.sorted { $0.alternativeScore.overall > $1.alternativeScore.overall }
        
#if DEBUG
        print("\n--- TOP 3 SORTED RESULTS ---")
        sortedResults.prefix(3).forEach { result in
            let timeString = timeFormatter.string(from: result.startTime)
            let score = String(format: "%.1f", result.alternativeScore.overall)
            print("[\(timeString)] Final Score: \(score)")
        }
        print("----------------------------\n")
#endif
        
        return Array(sortedResults.prefix(3))
    }
    
    // Add these three functions inside your UnifiedRouteAnalyticsEngine struct
    
    private func isValid(hour: Int, for preference: AppSettings.WakeUpPreference) -> Bool {
        switch preference {
        case .earlyBird:
            return hour >= 5 && hour <= 14 // Prefers morning/midday
        case .moderate:
            return hour >= 7 && hour <= 18 // Standard day hours
        case .nightOwl:
            return hour >= 9 && hour <= 20 // Prefers later starts
        }
    }
    
    private func generateWeatherPoints(for startTime: Date) -> [RouteWeatherPoint] {
        var newWeatherPoints: [RouteWeatherPoint] = []
        
        let totalDistanceMeters = weatherPoints.last?.distance ?? 0
        // Use the 'averageSpeed' property of the engine, converted to m/s
        let averageSpeedMPS = settings.units == .metric ? self.averageSpeed / 3.6 : self.averageSpeed * 0.44704
        
        guard averageSpeedMPS > 0 else { return weatherPoints }
        let rideDuration = totalDistanceMeters / averageSpeedMPS
        
        for point in weatherPoints {
            let timeAtPoint = startTime.addingTimeInterval(point.distance / totalDistanceMeters * rideDuration)
            
            var newWeather: DisplayWeatherModel = point.weather
            
            if let forecastForTime = getCurrentWeatherForTime(timeAtPoint) {
                newWeather = DisplayWeatherModel(
                    temp: forecastForTime.temp,
                    feelsLike: forecastForTime.feelsLike,
                    humidity: forecastForTime.humidity,
                    windSpeed: forecastForTime.windSpeed,
                    windDirection: getWindDirection(from: forecastForTime.windDeg),
                    windDeg: forecastForTime.windDeg,
                    description: forecastForTime.iconName,
                    iconName: forecastForTime.iconName,
                    pop: forecastForTime.pop,
                    visibility: nil,
                    uvIndex: forecastForTime.uvIndex
                )
            }
            
            let newPoint = RouteWeatherPoint(
                coordinate: point.coordinate,
                distance: point.distance,
                eta: timeAtPoint,
                weather: newWeather
            )
            newWeatherPoints.append(newPoint)
        }
        
        return newWeatherPoints
    }
    
    private func getWindDirection(from degrees: Int) -> String {
        switch degrees {
        case 0...22, 338...360: return "N"
        case 23...67: return "NE"
        case 68...112: return "E"
        case 113...157: return "SE"
        case 158...202: return "S"
        case 203...247: return "SW"
        case 248...292: return "W"
        case 293...337: return "NW"
        default: return "N/A"
        }
    }
    
    private func createDetailedComparison(
        alternativeTime: Date,
        currentScore: UnifiedRouteScore,
        alternativeScore: UnifiedRouteScore,
        alternativeEngine: UnifiedRouteAnalyticsEngine
    ) -> StartTimeComparison {
        
        let currentTemps = weatherPoints.map { $0.weather.temp }
        let alternativeTemps = alternativeEngine.weatherPoints.map { $0.weather.temp }
        
        let currentAvgTemp = currentTemps.reduce(0, +) / Double(currentTemps.count)
        let alternativeAvgTemp = alternativeTemps.reduce(0, +) / Double(alternativeTemps.count)
        
        let currentMaxWind = weatherPoints.map({ $0.weather.windSpeed }).max() ?? 0
        let alternativeMaxWind = alternativeEngine.weatherPoints.map({ $0.weather.windSpeed }).max() ?? 0
        
        let currentPop = weatherPoints.map({ $0.weather.pop }).max() ?? 0
        let alternativePop = alternativeEngine.weatherPoints.map({ $0.weather.pop }).max() ?? 0
        
        return StartTimeComparison(
            alternativeTime: alternativeTime,
            currentScore: currentScore,
            alternativeScore: alternativeScore,
            currentDaylight: self.safetyEngine.daylightAnalysis,
            alternativeDaylight: alternativeEngine.safetyEngine.daylightAnalysis,
            currentWind: self.windSummary,
            alternativeWind: alternativeEngine.windSummary,
            currentTemps: (min: currentTemps.min() ?? 0, max: currentTemps.max() ?? 0),
            alternativeTemps: (min: alternativeTemps.min() ?? 0, max: alternativeTemps.max() ?? 0),
            currentPop: currentPop,
            alternativePop: alternativePop,
            currentAvgTemp: currentAvgTemp,
            alternativeAvgTemp: alternativeAvgTemp,
            currentMaxWind: currentMaxWind,
            alternativeMaxWind: alternativeMaxWind,
            temperatureImprovement: abs(alternativeAvgTemp - settings.idealTemperature) - abs(currentAvgTemp - settings.idealTemperature),
            windImprovement: currentMaxWind - alternativeMaxWind,
            rainImprovementPercentage: (currentPop - alternativePop) * 100
        )
    }
    
    // MARK: - Weather Time Helper Functions Using Real HourlyForecast Data
    
    private func getCurrentWeatherForTime(_ time: Date) -> HourlyForecast? {
        // This is the check that was failing, now it will work.
        guard !cachedHourlyForecasts.isEmpty else {
#if DEBUG
            print("❌ ERROR: getCurrentWeatherForTime was called but cachedHourlyForecasts is empty.")
#endif
            return nil
        }
        
        // Find the single hourly forecast that is closest in time to the moment we need.
        let closestForecast = cachedHourlyForecasts.min { forecast1, forecast2 in
            abs(forecast1.date.timeIntervalSince(time)) < abs(forecast2.date.timeIntervalSince(time))
        }
                
        return closestForecast
    }
        
    // MARK: - Enhanced Comparison Functions
    
    private func getHumidityComparison(current: Date, alternative: Date) -> (current: Int, alternative: Int)? {
        guard let currentWeather = getCurrentWeatherForTime(current),
              let altWeather = getCurrentWeatherForTime(alternative) else {
            return nil
        }
        
        return (current: currentWeather.humidity, alternative: altWeather.humidity)
    }
    
    private func getUVComparison(current: Date, alternative: Date) -> (current: Double, alternative: Double)? {
        guard let currentWeather = getCurrentWeatherForTime(current),
              let altWeather = getCurrentWeatherForTime(alternative),
              let currentUV = currentWeather.uvIndex,
              let altUV = altWeather.uvIndex else {
            return nil
        }
        
        return (current: currentUV, alternative: altUV)
    }
    
    // MARK: - Personalized Benefit Generation
    
    private func generatePersonalizedBenefit(for comparison: StartTimeComparison) -> String {
        // Priority 1: Critical Safety Improvements
        if comparison.rainImprovementPercentage > 30 {
            return "Avoids \(Int(comparison.rainImprovementPercentage))% chance of rain"
        }
        
        if comparison.alternativeScore.safety > comparison.currentScore.safety + 20 {
            let darkDistanceReduction = comparison.currentDaylight.totalDarkDistance - comparison.alternativeDaylight.totalDarkDistance
            if darkDistanceReduction > 1000 {
                let miles = settings.units == .metric ? darkDistanceReduction / 1000 : darkDistanceReduction / 1609.34
                return "Avoids \(String(format: "%.1f", miles)) \(settings.units == .metric ? "km" : "mi") of riding in darkness"
            }
        }
        
        // Priority 2: Goal-Specific Improvements - SIMPLIFIED
        switch settings.primaryRidingGoal {
        case .performance:
            return generateDetailedPerformanceBenefit(for: comparison)
        case .enjoyment:
            return generateDetailedEnjoymentBenefit(for: comparison)
        case .commute:
            return generateDetailedCommuteBenefit(for: comparison)
        }
    }
    
    private func generateDetailedPerformanceBenefit(for comparison: StartTimeComparison) -> String {
        // Check if wind change is actually significant
        let windAnalysis = isWindChangeSignificant(
            currentMaxWind: comparison.currentMaxWind,
            alternativeMaxWind: comparison.alternativeMaxWind,
            currentWindSummary: comparison.currentWind,
            alternativeWindSummary: comparison.alternativeWind
        )
        
        // Only mention wind improvements if they're actually significant
        if windAnalysis.isSignificant && windAnalysis.type == .improvement &&
           settings.windTolerance != .windTolerant {
            let windUnit = settings.units.speedUnitAbbreviation
            let powerSavings = calculateWindPowerSavings(windImprovement: comparison.windImprovement)
            return "Reduced max winds (\(Int(comparison.alternativeMaxWind)) vs \(Int(comparison.currentMaxWind)) \(windUnit)) - saves ~\(powerSavings)% energy"
        }
        
        // Check for meaningful headwind/tailwind changes with wind speed thresholds
        let headwindReduction = comparison.currentWind.headwindPercentage - comparison.alternativeWind.headwindPercentage
        let tailwindIncrease = comparison.alternativeWind.tailwindPercentage - comparison.currentWind.tailwindPercentage
        
        // Only consider headwind/tailwind changes if the actual wind speeds are meaningful
        let avgCurrentWind = (comparison.currentMaxWind * 0.7) // Estimate average from max
        
        if headwindReduction > 20 && avgCurrentWind > WindThresholds.minMeaningfulWindSpeed {
            let timeImprovement = calculateHeadwindTimeSavings(headwindReduction: headwindReduction, distance: enhancedInsights.totalDistance)
            return "Reduces headwinds from \(Int(comparison.currentWind.headwindPercentage))% to \(Int(comparison.alternativeWind.headwindPercentage))% - saves ~\(timeImprovement) min"
        }
        
        let avgAlternativeWind = (comparison.alternativeMaxWind * 0.7)
        if tailwindIncrease > 15 && avgAlternativeWind > WindThresholds.minMeaningfulWindSpeed {
            let speedBoost = calculateTailwindSpeedBoost(tailwindIncrease: tailwindIncrease)
            return "Increases helpful tailwinds from \(Int(comparison.currentWind.tailwindPercentage))% to \(Int(comparison.alternativeWind.tailwindPercentage))% - \(speedBoost) mph faster avg"
        }
        
        // Temperature analysis (unchanged)
        if abs(comparison.temperatureImprovement) > (settings.units == .metric ? 3 : 5) {
            let currentDist = abs(comparison.currentAvgTemp - settings.idealTemperature)
            let altDist = abs(comparison.alternativeAvgTemp - settings.idealTemperature)
            
            if altDist < currentDist {
                let performanceGain = calculateTemperaturePerformanceGain(
                    currentTemp: comparison.currentAvgTemp,
                    alternativeTemp: comparison.alternativeAvgTemp,
                    idealTemp: settings.idealTemperature
                )
                return "Temperature closer to your ideal \(Int(settings.idealTemperature))\(settings.units.tempSymbol) (\(Int(comparison.alternativeAvgTemp))\(settings.units.tempSymbol) vs \(Int(comparison.currentAvgTemp))\(settings.units.tempSymbol)) - \(performanceGain)% better output"
            }
        }
        
        if comparison.currentAvgTemp > (settings.units == .metric ? 26 : 79) &&
           comparison.alternativeAvgTemp < comparison.currentAvgTemp - (settings.units == .metric ? 4 : 7) {
            return "Avoids heat stress zone (\(Int(comparison.alternativeAvgTemp))\(settings.units.tempSymbol) vs \(Int(comparison.currentAvgTemp))\(settings.units.tempSymbol)) - maintains power output"
        }
        
        return "Optimized conditions for power training"
    }

    private func generateDetailedEnjoymentBenefit(for comparison: StartTimeComparison) -> String {
        // Enhanced humidity analysis using HourlyForecast (unchanged)
        if let humidityComp = getHumidityComparison(current: rideStartTime, alternative: comparison.alternativeTime),
           humidityComp.current > 80 && humidityComp.alternative < humidityComp.current - 15 {
            return "Much less humid (\(humidityComp.alternative)% vs \(humidityComp.current)%) - significantly more comfortable"
        }
        
        // UV exposure analysis (unchanged)
        if let uvComp = getUVComparison(current: rideStartTime, alternative: comparison.alternativeTime),
           uvComp.current > 6 && uvComp.alternative < uvComp.current - 2 {
            return "Lower UV exposure (Index \(Int(uvComp.alternative)) vs \(Int(uvComp.current))) - gentler on skin"
        }
        
        // Temperature analysis (unchanged)
        if abs(comparison.temperatureImprovement) > (settings.units == .metric ? 2 : 4) {
            let currentDist = abs(comparison.currentAvgTemp - settings.idealTemperature)
            let altDist = abs(comparison.alternativeAvgTemp - settings.idealTemperature)
            
            if altDist < currentDist && settings.temperatureTolerance != .veryTolerant && settings.temperatureTolerance != .prefersCool {
                let comfortImprovement = Int(((currentDist - altDist) / currentDist) * 100)
                return "Much closer to your ideal \(Int(settings.idealTemperature))\(settings.units.tempSymbol) (\(Int(comparison.alternativeAvgTemp))\(settings.units.tempSymbol) vs \(Int(comparison.currentAvgTemp))\(settings.units.tempSymbol)) - \(comfortImprovement)% more comfortable"
            }
        }
        
        // Wind analysis with meaningful thresholds
        let windAnalysis = isWindChangeSignificant(
            currentMaxWind: comparison.currentMaxWind,
            alternativeMaxWind: comparison.alternativeMaxWind,
            currentWindSummary: comparison.currentWind,
            alternativeWindSummary: comparison.alternativeWind
        )
        
        if windAnalysis.isSignificant && windAnalysis.type == .improvement {
            let windUnit = settings.units.speedUnitAbbreviation
            let stabilityImprovement = calculateWindStability(windImprovement: comparison.windImprovement)
            return "Calmer conditions (\(Int(comparison.alternativeMaxWind)) vs \(Int(comparison.currentMaxWind)) \(windUnit) max wind) - \(stabilityImprovement)% less bike handling effort"
        }
        
        // Rest unchanged...
        let goldenHourImprovement = comparison.alternativeDaylight.goldenHourSegments.count - comparison.currentDaylight.goldenHourSegments.count
        if goldenHourImprovement > 0 {
            let goldenDistance = comparison.alternativeDaylight.goldenHourSegments.reduce(0) { $0 + $1.distance }
            let miles = settings.units == .metric ? goldenDistance / 1000 : goldenDistance / 1609.34
            return "More golden hour riding (\(String(format: "%.1f", miles)) \(settings.units == .metric ? "km" : "mi") of perfect lighting)"
        }
        
        let visibilityImprovement = comparison.alternativeScore.daylight - comparison.currentScore.daylight
        if visibilityImprovement > 10 {
            return "Better scenic visibility with \(Int(visibilityImprovement))% more optimal lighting"
        }
        
        if comparison.currentAvgTemp > (settings.units == .metric ? 24 : 75) &&
           comparison.alternativeAvgTemp < comparison.currentAvgTemp - (settings.units == .metric ? 3 : 5) {
            return "Reduced sun exposure (\(Int(comparison.alternativeAvgTemp))\(settings.units.tempSymbol) vs \(Int(comparison.currentAvgTemp))\(settings.units.tempSymbol)) - gentler on skin"
        }
        
        return "Notably more comfortable riding conditions"
    }

    private func generateDetailedCommuteBenefit(for comparison: StartTimeComparison) -> String {
        let daylightImprovement = comparison.alternativeScore.daylight - comparison.currentScore.daylight
        if daylightImprovement > 15 {
            let visibilityGain = Int(daylightImprovement)
            return "Much better visibility for safer commuting (\(visibilityGain)% improvement in lighting conditions)"
        }
        
        // Headwind analysis with meaningful thresholds
        let headwindReduction = comparison.currentWind.headwindPercentage - comparison.alternativeWind.headwindPercentage
        let avgCurrentWind = comparison.currentMaxWind * 0.7
        
        if headwindReduction > 15 && avgCurrentWind > WindThresholds.minMeaningfulWindSpeed {
            let timeReliability = calculateCommuteTimeReliability(headwindReduction: headwindReduction)
            return "More predictable commute time with \(Int(headwindReduction))% less headwinds - \(timeReliability) min more reliable"
        }
        
        if comparison.rainImprovementPercentage > 15 {
            return "Lower chance of arriving soaked (\(Int(comparison.currentPop * 100))% to \(Int(comparison.alternativePop * 100))% rain chance)"
        }
        
        if comparison.currentAvgTemp > (settings.units == .metric ? 27 : 81) &&
           comparison.alternativeAvgTemp < comparison.currentAvgTemp - (settings.units == .metric ? 4 : 7) {
            return "Cooler conditions (\(Int(comparison.alternativeAvgTemp))\(settings.units.tempSymbol) vs \(Int(comparison.currentAvgTemp))\(settings.units.tempSymbol)) - more pleasant interactions with traffic"
        }
        
        // Wind analysis with meaningful thresholds
        let windAnalysis = isWindChangeSignificant(
            currentMaxWind: comparison.currentMaxWind,
            alternativeMaxWind: comparison.alternativeMaxWind,
            currentWindSummary: comparison.currentWind,
            alternativeWindSummary: comparison.alternativeWind
        )
        
        if windAnalysis.isSignificant && windAnalysis.type == .improvement {
            return "Reduced wind (\(Int(comparison.alternativeMaxWind)) vs \(Int(comparison.currentMaxWind)) mph) - lighter gear needed"
        }
        
        return "More reliable and safer commuting conditions"
    }

    // MARK: - Performance Calculation Helpers
    
    private func calculateWindPowerSavings(windImprovement: Double) -> Int {
        let powerReduction = pow(windImprovement / 20, 1.5) * 15
        return min(25, max(5, Int(powerReduction)))
    }
    
    private func calculateHeadwindTimeSavings(headwindReduction: Double, distance: Double) -> Int {
        let timeSavingsPercentage = (headwindReduction / 10) * 2
        let baseTotalMinutes = (distance / (averageSpeed / 3.6)) / 60
        let timeSavings = baseTotalMinutes * (timeSavingsPercentage / 100)
        return max(1, Int(timeSavings))
    }
    
    private func calculateTemperaturePerformanceGain(currentTemp: Double, alternativeTemp: Double, idealTemp: Double) -> Int {
        let currentDeviation = abs(currentTemp - idealTemp)
        let alternativeDeviation = abs(alternativeTemp - idealTemp)
        let improvement = (currentDeviation - alternativeDeviation) / currentDeviation
        
        let performanceGain = improvement * (settings.units == .metric ? 3 : 2)
        return min(15, max(2, Int(performanceGain * 100)))
    }
    
    private func calculateTailwindSpeedBoost(tailwindIncrease: Double) -> String {
        let speedBoost = (tailwindIncrease / 100) * 3
        return String(format: "%.1f", speedBoost)
    }
    
    private func calculateWindStability(windImprovement: Double) -> Int {
        let stabilityGain = (windImprovement / 15) * 20
        return min(30, max(10, Int(stabilityGain)))
    }
    
    private func calculateCommuteTimeReliability(headwindReduction: Double) -> Int {
        let reliabilityGain = (headwindReduction / 20) * 5
        return max(2, Int(reliabilityGain))
    }
    
    // MARK: - Smart Tradeoff Analysis (Updated with Fixed Logic)
    
    
    private func generateSmartTradeoff(for comparison: StartTimeComparison) -> String? {
        let calendar = Calendar.current
        let alternativeComponents = calendar.dateComponents([.hour], from: comparison.alternativeTime)
        let currentComponents = calendar.dateComponents([.hour], from: rideStartTime)
        
        guard let alternativeHour = alternativeComponents.hour,
              let currentHour = currentComponents.hour else { return nil }
        
        // Calculate actual time difference accounting for day boundaries
        let timeDifference = comparison.alternativeTime.timeIntervalSince(rideStartTime)
        let hoursDifference = timeDifference / 3600.0
        
        // 1. Wake-up time tradeoffs
        if hoursDifference < 0 { // Alternative is earlier
            let absHoursDifference = abs(hoursDifference)
            
            // Only flag unreasonable early times based on user preference
            switch settings.wakeUpEarliness {
            case .nightOwl:
                if absHoursDifference >= 2 && alternativeHour < 8 {
                    return "Requires waking up \(Int(absHoursDifference)) hours earlier"
                } else if alternativeHour < 7 {
                    return "Early start may be challenging"
                }
            case .moderate:
                if alternativeHour < 6 {
                    return "Very early start required"
                } else if absHoursDifference >= 3 {
                    return "Requires waking up \(Int(absHoursDifference)) hours earlier"
                }
            case .earlyBird:
                if alternativeHour < 5 {
                    return "Extremely early start required"
                }
            }
        } else if hoursDifference > 0 { // Alternative is later
            switch settings.wakeUpEarliness {
            case .earlyBird:
                if hoursDifference >= 3 {
                    return "Later start than you might prefer"
                }
            case .moderate:
                if alternativeHour > 18 {
                    return "Late afternoon start"
                }
            case .nightOwl:
                break // Night owls are fine with later starts
            }
        }
        
        // 2. Temperature tradeoffs - Fixed Logic
        let tempDifference = comparison.alternativeAvgTemp - comparison.currentAvgTemp
        let significantTempChange = settings.units == .metric ? 4.0 : 7.0
        
        if abs(tempDifference) > significantTempChange {
            switch settings.temperatureTolerance {
            case .verySensitive, .prefersWarm:
                if tempDifference < -significantTempChange {
                    return "Cooler conditions (\(Int(comparison.alternativeAvgTemp))°\(settings.units.tempSymbol) vs \(Int(comparison.currentAvgTemp))°\(settings.units.tempSymbol))"
                }
            case .prefersCool:
                if tempDifference > significantTempChange {
                    return "Warmer conditions (\(Int(comparison.alternativeAvgTemp))°\(settings.units.tempSymbol) vs \(Int(comparison.currentAvgTemp))°\(settings.units.tempSymbol))"
                }
            case .neutral:
                let currentDistanceFromIdeal = abs(comparison.currentAvgTemp - settings.idealTemperature)
                let alternativeDistanceFromIdeal = abs(comparison.alternativeAvgTemp - settings.idealTemperature)
                
                if alternativeDistanceFromIdeal > currentDistanceFromIdeal + significantTempChange {
                    return "Further from your ideal temperature (\(Int(comparison.alternativeAvgTemp))\(settings.units.tempSymbol) vs ideal \(Int(settings.idealTemperature))\(settings.units.tempSymbol))"
                }
            case .veryTolerant:
                let extremeTempChange = settings.units == .metric ? 8.0 : 15.0
                if abs(tempDifference) > extremeTempChange {
                    if tempDifference > 0 {
                        return "Much warmer conditions (\(Int(comparison.alternativeAvgTemp))°\(settings.units.tempSymbol) vs \(Int(comparison.currentAvgTemp))°\(settings.units.tempSymbol))"
                    } else {
                        return "Much cooler conditions (\(Int(comparison.alternativeAvgTemp))°\(settings.units.tempSymbol) vs \(Int(comparison.currentAvgTemp))°\(settings.units.tempSymbol))"
                    }
                }
            }
        }
        
        // 3. Safety tradeoffs for longer rides
        let isLongRide = enhancedInsights.totalDistance > (settings.units == .metric ? 50000 : 31000)
        if isLongRide {
            let rideDuration = (enhancedInsights.totalDistance / averageSpeed) * 3600
            let alternativeEndTime = comparison.alternativeTime.addingTimeInterval(rideDuration)
            let sunsetTime = comparison.alternativeDaylight.sunset
            
            if alternativeEndTime > sunsetTime.addingTimeInterval(-3600) {
                return "May finish close to sunset on this longer ride"
            }
            
            let currentDarkDistance = comparison.currentDaylight.totalDarkDistance
            let alternativeDarkDistance = comparison.alternativeDaylight.totalDarkDistance
            
            if alternativeDarkDistance > currentDarkDistance + 5000 { // 5km more darkness
                let additionalDarkMiles = (alternativeDarkDistance - currentDarkDistance) / (settings.units == .metric ? 1000 : 1609.34)
                return "Additional \(String(format: "%.1f", additionalDarkMiles)) \(settings.units == .metric ? "km" : "mi") in darkness"
            }
        }
        
        // 4. Wind tradeoffs - only flag if significantly worse AND above meaningful thresholds
        let windAnalysis = isWindChangeSignificant(
            currentMaxWind: comparison.currentMaxWind,
            alternativeMaxWind: comparison.alternativeMaxWind,
            currentWindSummary: comparison.currentWind,
            alternativeWindSummary: comparison.alternativeWind
        )

        if windAnalysis.isSignificant &&
           windAnalysis.type == .degradation &&
           settings.windTolerance == .windSensitive &&
           comparison.alternativeMaxWind >= WindThresholds.strongWindThreshold {
            return "Stronger winds (\(Int(comparison.alternativeMaxWind)) vs \(Int(comparison.currentMaxWind)) \(settings.units.speedUnitAbbreviation))"
        }
        
        // 5. Rain tradeoffs - only flag if notably higher chance
        let rainIncrease = (comparison.alternativePop - comparison.currentPop) * 100
        if rainIncrease > 20 {
            return "Higher chance of rain (\(Int(comparison.alternativePop * 100))% vs \(Int(comparison.currentPop * 100))%)"
        }
        
        return nil
    }
}

// MARK: - Unified Data Models

struct ComprehensiveRouteAnalysis {
    let overallScore: UnifiedRouteScore
    let safetyScore: SafetyScore
    let daylightAnalysis: DaylightAnalysis
    let weatherSafety: WeatherSafetyAnalysis
    let criticalInsights: [CriticalRideInsight]
    let routeSegments: [EnhancedRouteSegment]
    let unifiedRecommendations: [UnifiedRecommendation]
    let betterStartTimes: [OptimalStartTime]
    let weatherFeel: WeatherFeel
    let windSummary: WindSummary
    let powerAnalysis: PowerRouteAnalysisResult?
    let weatherPoints: [RouteWeatherPoint]
    let settings: AppSettings
    let elevationAnalysis: ElevationAnalysis?

    var temperatureRangeFormatted: String {
        let temps = weatherPoints.map { $0.weather.temp }
        guard let min = temps.min(), let max = temps.max() else { return "N/A" }
        let unit = settings.units.tempSymbol
        return "\(Int(min))\(unit) - \(Int(max))\(unit)"
    }

}

struct UnifiedRouteScore {
    let overall: Double
    let safety: Double
    let weather: Double
    let daylight: Double
    let rating: UnifiedRating
}

enum UnifiedRating {
    case excellent, good, fair, caution, dangerous
    
    var color: Color {
        switch self {
        case .excellent: return .mint
        case .good: return .green
        case .fair: return .yellow
        case .caution: return .orange
        case .dangerous: return .red
        }
    }
    
    var label: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .caution: return "Use Caution"
        case .dangerous: return "Not Recommended"
        }
    }
    
    var emoji: String {
        switch self {
        case .excellent: return "🌟"
        case .good: return "✅"
        case .fair: return "⚠️"
        case .caution: return "🚨"
        case .dangerous: return "⛔️"
        }
    }
    
    static func from(score: Double) -> UnifiedRating {
        switch score {
        case 85...100: return .excellent
        case 70..<85: return .good
        case 55..<70: return .fair
        case 30..<55: return .caution
        default: return .dangerous
        }
    }
}

struct UnifiedRecommendation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let icon: String
    let priority: Priority
    
    enum Priority {
        case critical, important, moderate, low
        
        var color: Color {
            switch self {
            case .critical: return .red
            case .important: return .orange
            case .moderate: return .yellow
            case .low: return .green
            }
        }
        
        var emoji: String {
            switch self {
            case .critical: return "🚨"
            case .important: return "⚠️"
            case .moderate: return "ℹ️"
            case .low: return "✅"
            }
        }
    }
}

struct OptimalStartTime: Identifiable {
    let id = UUID()
    let startTime: Date
    let improvementPercentage: Int
    let primaryBenefit: String
    let tradeoff: String?
    let window: (start: Date, end: Date)
    let alternativeScore: UnifiedRouteScore // Add this property
}
