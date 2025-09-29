//
//  RideCalories.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 9/15/25.
//

import Foundation

struct RideEnergySegment {
    let segmentIndex: Int
    let energyKJ: Double
    let calories: Double
}

struct RideEnergyResult {
    let totalEnergyKJ: Double
    let totalCalories: Double
    let segments: [RideEnergySegment]
}

