//
//  DataSource.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 12/7/25.
//


import Foundation

// MARK: - Data Source Enum
// Add this to your project - it's the only missing piece!
enum DataSource: String, Codable {
    case appleHealth = "Apple Health"
    case garmin = "Garmin"
    case manual = "Manual Entry"
}