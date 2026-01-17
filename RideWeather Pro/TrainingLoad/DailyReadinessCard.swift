
//
//  DailyReadinessCard.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 11/9/25.
//

import SwiftUI

struct DailyReadinessCard: View {
    let readiness: PhysiologicalReadiness
    @ObservedObject private var wellnessManager = WellnessManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                CardHeaderWithInfo(
                    title: "Daily Readiness",
                    infoTitle: "Daily Readiness",
                    infoMessage: "Combines HRV, resting heart rate, and sleep quality from Apple Health to assess your body's readiness for intense training. Updated daily based on last night's data."
                )
                
                Spacer()
                
                // Data source indicator
                dataSourceBadge
                
                Text("\(readiness.readinessScore)%")
                    .font(.title2.weight(.bold))
                    .foregroundColor(readinessColor)
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                
                // HRV
                RecoveryMetric(
                    title: "HRV",
                    value: readiness.latestHRV,
                    average: readiness.averageHRV,
                    format: "%.0f ms",
                    isInverted: false
                )
                
                // RHR
                RecoveryMetric(
                    title: "Resting HR",
                    value: readiness.latestRHR,
                    average: readiness.averageRHR,
                    format: "%.0f bpm",
                    isInverted: true // Lower is better
                )
                
                // Sleep
                RecoveryMetric(
                    title: "Sleep",
                    value: readiness.sleepDuration, // in seconds
                    average: readiness.averageSleepDuration, // 7d avg in seconds
                    format: "%.0fh %.0fm", // Special format
                    isInverted: false
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // Show where the data is coming from
    private var dataSourceBadge: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Check if today's data came from Garmin
        let hasGarminData = wellnessManager.dailyMetrics.contains {
            calendar.isDate($0.date, inSameDayAs: today)
        }
        
        let config = DataSourceManager.shared.configuration
        let isUsingGarmin = config.wellnessSource == .garmin
        
        return HStack(spacing: 4) {
            if isUsingGarmin && hasGarminData {
                Image(systemName: "heart.circle.fill")
                    .font(.caption)
                Text("Garmin")
                    .font(.caption2)
                    .fontWeight(.semibold)
            } else {
                Image(systemName: "applelogo")
                    .font(.caption)
                Text("Health")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
        }
        .foregroundColor(isUsingGarmin && hasGarminData ? .red : .gray)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private var readinessColor: Color {
        switch readiness.readinessScore {
        case 85...: return .green
        case 70..<85: return .blue
        case 50..<70: return .orange
        default: return .red
        }
    }
}

// MARK: - RecoveryMetric Helper

struct RecoveryMetric: View {
    let title: String
    let value: Double?
    let average: Double? // This will be nil if no 7d avg exists
    let format: String
    var isInverted: Bool = false
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Main Value
            Text(formattedValue(value, format: format))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            // Trend Text (e.g., "+3.9 ms" or "7h 15m avg")
            Text(trendString)
                .font(.caption2)
                .foregroundColor(trendColor)
        }
    }
    
    private func formattedValue(_ val: Double?, format: String) -> String {
        guard let val = val else { return "N/A" }
        
        if format.contains("h") { // Special case for sleep
            let hours = Int(val) / 3600
            let minutes = (Int(val) % 3600) / 60
            return "\(hours)h \(minutes)m"
        } else {
            return String(format: format, val)
        }
    }
    
    private var trendString: String {
        guard let value = value, let average = average else {
            return "vs 7d Avg" // Default text if no avg data
        }
        
        // For Sleep, show the 7d avg, not the difference
        if title == "Sleep" {
            let avgString = formattedValue(average, format: "%.0fh %.0fm")
            return "\(avgString) (7d avg)"
        }
        
        let trend = value - average
        let prefix = trend >= 0 ? "+" : ""
        let trendNumString: String
        
        if format.contains("ms") {
            trendNumString = String(format: "\(prefix)%.1f", trend)
        } else { // "bpm"
            trendNumString = String(format: "\(prefix)%.1f", trend)
        }
        
        // Add "vs 7d Avg" to HRV/RHR
        return "\(trendNumString) vs 7d Avg"
    }
    
    private var trendColor: Color {
        guard let value = value, let average = average else {
            return .secondary
        }
        
        let trend = value - average
        
        let tolerance: Double
        if title == "Sleep" {
            // Color based on sleep vs. its 7d average
            tolerance = 0.25 * 3600 // 15 minutes tolerance
        } else {
            // Color based on HRV/RHR vs. their 7d average
            tolerance = max(0.1, average * 0.01) // 1% tolerance
        }
        
        if (trend > tolerance && !isInverted) || (trend < -tolerance && isInverted) {
            return .green // Good trend
        } else if (trend < -tolerance && !isInverted) || (trend > tolerance && isInverted) {
            return .orange // Bad trend
        } else {
            return .secondary // Neutral
        }
    }
}
