//
//  RideETA.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 9/15/25.
//

import Foundation

struct RideETASegment {
    let segmentIndex: Int
    let distanceMeters: Double
    let suggestedPowerWatts: Double
    let estimatedTimeSeconds: Double
}

struct RideETAResult {
    let totalTimeSeconds: Double
    let segments: [RideETASegment]
}

