//
//  WeeklyView.swift
//  RideWeatherWatch Watch App
//

import SwiftUI

struct WeeklyView: View {
    let weekStats: WeeklyStats
    let weatherAlert: WeatherAlert?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // HEADER
                VStack(spacing: 4) {
                    Text("THIS WEEK")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    
                    Text("Training Summary")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
                
                // MAIN STATS GRID
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    BigStat(
                        value: "\(weekStats.rideCount)",
                        label: "Workouts",
                        emoji: "💪"
                    )
                    
                    BigStat(
                        value: String(format: "%.1fh", weekStats.totalHours),
                        label: "Time",
                        emoji: "⏱️"
                    )
                    
                    BigStat(
                        value: "\(Int(weekStats.totalDistance))",
                        label: "Miles",
                        emoji: "📍"
                    )
                    
                    BigStat(
                        value: weekStats.fitnessChange > 0 ? "+\(Int(weekStats.fitnessChange))" : "\(Int(weekStats.fitnessChange))",
                        label: "Fitness",
                        emoji: "📈",
                        color: weekStats.fitnessChange > 0 ? .green : .red
                    )
                }
                
                Divider()
                
                // INSIGHTS
                VStack(spacing: 6) {
                    InsightCard(
                        icon: weekStats.fitnessChange > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
                        iconColor: weekStats.fitnessChange > 0 ? .green : .orange,
                        text: "CTL \(weekStats.fitnessChange > 0 ? "increased" : "decreased") by \(abs(Int(weekStats.fitnessChange))) this week"
                    )
                    
                    if let nextRest = weekStats.nextRestDay {
                        InsightCard(
                            icon: "bed.double.fill",
                            iconColor: .blue,
                            text: "Next rest day: \(nextRest)"
                        )
                    }
                    
                    if weekStats.rampRate > 8 {
                        InsightCard(
                            icon: "exclamationmark.triangle.fill",
                            iconColor: .red,
                            text: "Building too fast - risk of overtraining"
                        )
                    } else if weekStats.rampRate < -5 {
                        InsightCard(
                            icon: "arrow.down.circle.fill",
                            iconColor: .orange,
                            text: "Fitness declining - add volume"
                        )
                    }
                }
                
                // WEATHER ALERT
                if let alert = weatherAlert {
                    WeatherAlertView(alert: alert)
                }
            }
            .padding()
        }
        .containerBackground(.indigo.gradient, for: .tabView)
    }
}

// MARK: - Big Stat Card

struct BigStat: View {
    let value: String
    let label: String
    let emoji: String
    var color: Color = .white
    
    var body: some View {
        VStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 24))
            
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(color)
            
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Insight Card

struct InsightCard: View {
    let icon: String
    let iconColor: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(iconColor)
                .frame(width: 16)
            
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Weather Alert View

struct WeatherAlertView: View {
    let alert: WeatherAlert
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: alert.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(alert.color)
                
                Text("Weather Alert")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(alert.color)
            }
            
            Text(alert.message)
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(alert.color.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(alert.color.opacity(0.5), lineWidth: 1)
        )
    }
}

// MARK: - Supporting Models

struct WeeklyStats {
    let rideCount: Int
    let totalHours: Double
    let totalDistance: Double // in miles
    let fitnessChange: Double // CTL change
    let rampRate: Double
    let nextRestDay: String?
    
    static func calculate(from history: [DailyTrainingLoad]) -> WeeklyStats {
        let calendar = Calendar.current
        let today = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        
        // Get last 7 days
        let lastWeek = history.filter { $0.date >= weekAgo }
        
        // Count rides
        let rideCount = lastWeek.filter { $0.rideCount > 0 }.count
        
        // Total hours and distance
        let totalSeconds = lastWeek.reduce(0) { $0 + $1.totalDuration }
        let totalHours = totalSeconds / 3600
        let totalMeters = lastWeek.reduce(0) { $0 + $1.totalDistance }
        let totalMiles = totalMeters * 0.000621371
        
        // Fitness change (CTL now vs 7 days ago)
        let currentCTL = history.last?.ctl ?? 0
        let weekAgoCTL = history.first(where: { 
            calendar.isDate($0.date, inSameDayAs: weekAgo) 
        })?.ctl ?? currentCTL
        let fitnessChange = currentCTL - weekAgoCTL
        
        // Ramp rate (from TrainingLoadSummary)
        let rampRate = fitnessChange // This is already TSS/week
        
        // Next rest day logic
        let nextRestDay: String?
        if rideCount >= 5 {
            nextRestDay = "Tomorrow"
        } else if rideCount >= 3 {
            let daysOff = 7 - rideCount
            nextRestDay = daysOff == 1 ? "Today" : "In \(daysOff) days"
        } else {
            nextRestDay = nil
        }
        
        return WeeklyStats(
            rideCount: rideCount,
            totalHours: totalHours,
            totalDistance: totalMiles,
            fitnessChange: fitnessChange,
            rampRate: rampRate,
            nextRestDay: nextRestDay
        )
    }
}


