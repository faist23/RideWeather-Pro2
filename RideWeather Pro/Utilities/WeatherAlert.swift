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
        case .warning: return "exclamationmark.triangle.fill"
        case .watch: return "eye.fill" // Distinct icon for "Watch"
        case .advisory: return "cloud.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    
    var color: Color {
        switch severity {
        case .severe: return Color(red: 147/255, green: 11/255, blue: 0/255) // Dark Red
        case .warning: return .orange
        case .watch: return .yellow
        case .advisory: return .yellow.opacity(0.8)
        case .unknown: return .gray
        }
    }
    
    // Smart Text Color (Black for Yellow/Orange, White for Red)
    var textColor: Color {
        switch severity {
        case .advisory, .warning, .watch: return .black // Fixes readability on Yellow/Orange
        case .severe, .unknown: return .white           // White looks best on Red/Gray
        }
    }
    
    // Explicitly define all cases to match the rest of the app's logic
    enum Severity: String, Codable {
        case severe
        case warning
        case watch
        case advisory
        case unknown
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
