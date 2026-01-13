//
//  WeatherAlert.swift
//  RideWeather Pro
//

import Foundation
import SwiftUI

struct WeatherAlert: Codable, Identifiable {
    let id: UUID
    let message: String
    let severity: Severity
    
    init(id: UUID = UUID(), message: String, severity: Severity) {
        self.id = id
        self.message = message
        self.severity = severity
    }
    
    var icon: String {
        switch severity {
        case .severe: return "exclamationmark.triangle.fill"
        case .warning: return "cloud.rain.fill"
        case .advisory: return "cloud.fill"
        }
    }
    
    var color: Color {
        switch severity {
        case .severe: return .red
        case .warning: return .orange
        case .advisory: return .yellow
        }
    }
    
    enum Severity: String, Codable {
        case severe
        case warning
        case advisory
    }
}
