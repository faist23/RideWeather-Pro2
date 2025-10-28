//
//  PacingEngine+Codable.swift
//  RideWeather Pro
//
//  Codable conformance for pacing plan types
//

import Foundation

// MARK: - PowerZone Codable
extension PowerZone: Codable {
    // Manual implementation needed because extension is outside original file
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decode(Int.self, forKey: .number)
        name = try container.decode(String.self, forKey: .name)
        minPower = try container.decode(Double.self, forKey: .minPower)
        maxPower = try container.decode(Double.self, forKey: .maxPower)
        color = try container.decode(String.self, forKey: .color)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(number, forKey: .number)
        try container.encode(name, forKey: .name)
        try container.encode(minPower, forKey: .minPower)
        try container.encode(maxPower, forKey: .maxPower)
        try container.encode(color, forKey: .color)
    }
    
    enum CodingKeys: String, CodingKey {
        case number, name, minPower, maxPower, color
    }
}

// MARK: - PowerRouteSegment Codable
extension PowerRouteSegment: Codable {
    enum CodingKeys: String, CodingKey {
        case startPoint, endPoint, distanceMeters, elevationGrade
        case averageHeadwindMps, averageCrosswindMps, averageTemperatureC
        case averageHumidity, calculatedSpeedMps, timeSeconds
        case powerRequired, segmentType
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startPoint = try container.decode(RouteWeatherPoint.self, forKey: .startPoint)
        endPoint = try container.decode(RouteWeatherPoint.self, forKey: .endPoint)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        elevationGrade = try container.decode(Double.self, forKey: .elevationGrade)
        averageHeadwindMps = try container.decode(Double.self, forKey: .averageHeadwindMps)
        averageCrosswindMps = try container.decode(Double.self, forKey: .averageCrosswindMps)
        averageTemperatureC = try container.decode(Double.self, forKey: .averageTemperatureC)
        averageHumidity = try container.decode(Double.self, forKey: .averageHumidity)
        calculatedSpeedMps = try container.decode(Double.self, forKey: .calculatedSpeedMps)
        timeSeconds = try container.decode(Double.self, forKey: .timeSeconds)
        powerRequired = try container.decode(Double.self, forKey: .powerRequired)
        segmentType = try container.decode(SegmentType.self, forKey: .segmentType)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startPoint, forKey: .startPoint)
        try container.encode(endPoint, forKey: .endPoint)
        try container.encode(distanceMeters, forKey: .distanceMeters)
        try container.encode(elevationGrade, forKey: .elevationGrade)
        try container.encode(averageHeadwindMps, forKey: .averageHeadwindMps)
        try container.encode(averageCrosswindMps, forKey: .averageCrosswindMps)
        try container.encode(averageTemperatureC, forKey: .averageTemperatureC)
        try container.encode(averageHumidity, forKey: .averageHumidity)
        try container.encode(calculatedSpeedMps, forKey: .calculatedSpeedMps)
        try container.encode(timeSeconds, forKey: .timeSeconds)
        try container.encode(powerRequired, forKey: .powerRequired)
        try container.encode(segmentType, forKey: .segmentType)
    }
}

// MARK: - PacingSummary Codable
extension PacingSummary: Codable {
    enum CodingKeys: String, CodingKey {
        case totalElevation, timeInZones, keySegments, warnings
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalElevation = try container.decode(Double.self, forKey: .totalElevation)
        timeInZones = try container.decode([Int: Double].self, forKey: .timeInZones)
        keySegments = try container.decode([KeySegment].self, forKey: .keySegments)
        warnings = try container.decode([String].self, forKey: .warnings)
        settings = AppSettings()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(totalElevation, forKey: .totalElevation)
        try container.encode(timeInZones, forKey: .timeInZones)
        try container.encode(keySegments, forKey: .keySegments)
        try container.encode(warnings, forKey: .warnings)
    }
}

// MARK: - PacingPlan Codable
extension PacingPlan: Codable {
    enum CodingKeys: String, CodingKey {
        case segments, strategy, totalTimeMinutes, totalDistance
        case averagePower, normalizedPower, estimatedTSS, intensityFactor
        case difficulty, startTime, estimatedArrival, ftp
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        segments = try container.decode([PacedSegment].self, forKey: .segments)
        strategy = try container.decode(PacingStrategy.self, forKey: .strategy)
        totalTimeMinutes = try container.decode(Double.self, forKey: .totalTimeMinutes)
        totalDistance = try container.decode(Double.self, forKey: .totalDistance)
        averagePower = try container.decode(Double.self, forKey: .averagePower)
        normalizedPower = try container.decode(Double.self, forKey: .normalizedPower)
        estimatedTSS = try container.decode(Double.self, forKey: .estimatedTSS)
        intensityFactor = try container.decode(Double.self, forKey: .intensityFactor)
        difficulty = try container.decode(DifficultyRating.self, forKey: .difficulty)
        startTime = try container.decode(Date.self, forKey: .startTime)
        estimatedArrival = try container.decode(Date.self, forKey: .estimatedArrival)
        ftp = try container.decode(Double.self, forKey: .ftp)
        
        summary = PacingSummary(
            totalElevation: 0,
            timeInZones: [:],
            keySegments: [],
            warnings: [],
            settings: AppSettings()
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(segments, forKey: .segments)
        try container.encode(strategy.rawValue, forKey: .strategy)  // FIX: Encode rawValue
        try container.encode(totalTimeMinutes, forKey: .totalTimeMinutes)
        try container.encode(totalDistance, forKey: .totalDistance)
        try container.encode(averagePower, forKey: .averagePower)
        try container.encode(normalizedPower, forKey: .normalizedPower)
        try container.encode(estimatedTSS, forKey: .estimatedTSS)
        try container.encode(intensityFactor, forKey: .intensityFactor)
        try container.encode(difficulty.rawValue, forKey: .difficulty)  // FIX: Encode rawValue
        try container.encode(startTime, forKey: .startTime)
        try container.encode(estimatedArrival, forKey: .estimatedArrival)
        try container.encode(ftp, forKey: .ftp)
    }
}
