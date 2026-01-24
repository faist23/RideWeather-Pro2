//
//  WeatherAlert.swift
//  RideWeather Pro
//

import Foundation
import SwiftUI

struct WeatherAlert: Codable, Identifiable {
    let id: UUID
    let message: String      // Short title (e.g. "Special Weather Statement")
    let description: String  // Full details from API
    let severity: Severity
    
    init(id: UUID = UUID(), message: String, description: String, severity: Severity) {
        self.id = id
        self.message = message
        self.description = description
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
        case .severe: return Color(red: 147/255, green: 11/255, blue: 0/255) // Darker red for better contrast
        case .warning: return .orange
        case .advisory: return .yellow
        }
    }
    
    // Smart Text Color (Black for Yellow/Orange, White for Red)
    var textColor: Color {
        switch severity {
        case .advisory, .warning: return .black // Fixes readability on Yellow/Orange
        case .severe: return .white             // White looks best on Red
        }
    }
    
    enum Severity: String, Codable {
        case severe
        case warning
        case advisory
    }
    
    var cleanDescription: String {
        // 1. Replace double newlines (paragraphs) with a unique placeholder
        let paragraphsPreserved = description
            .replacingOccurrences(of: "\n\n", with: "[[PARAGRAPH]]")
        
        // 2. Replace single newlines (hard wraps) with a space
        let singleLinesRemoved = paragraphsPreserved.replacingOccurrences(of: "\n", with: " ")
        
        // 3. Restore paragraphs and trim whitespace
        return singleLinesRemoved
            .replacingOccurrences(of: "[[PARAGRAPH]]", with: "\n\n")
            .replacingOccurrences(of: "  ", with: " ") // Remove accidental double spaces
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
