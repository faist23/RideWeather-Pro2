//
//  RecoveryStatusCard.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 1/15/26.
//

/*import SwiftUI

struct RecoveryStatusCard: View {
    let recovery: RecoveryStatus
    let wellness: DailyWellnessMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recovery Status")
                    .font(.headline)
                
                Spacer()
                
                Text("\(recovery.recoveryPercent)%")
                    .font(.title2.weight(.bold))
                    .foregroundColor(recoveryColor)
            }
            
            // Recovery gauge
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                        .frame(height: 12)
                    
                    // Fill
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.red, .orange, .yellow, .green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(recovery.recoveryPercent) / 100, height: 12)
                }
            }
            .frame(height: 12)
            
            // Key metrics
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                RecoveryMetricCompact(
                    title: "Time Since Ride",
                    value: recovery.timeSinceRide,
                    icon: "clock"
                )
                
                RecoveryMetricCompact(
                    title: "HRV Status",
                    value: recovery.hrvStatus,
                    icon: "waveform.path.ecg"
                )
                
                RecoveryMetricCompact(
                    title: "Sleep Quality",
                    value: recovery.sleepStatus,
                    icon: "bed.double.fill"
                )
            }
            
            // Recommendation
            Text(recovery.recommendation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var recoveryColor: Color {
        switch recovery.recoveryPercent {
        case 85...: return .green
        case 70..<85: return .blue
        case 50..<70: return .orange
        default: return .red
        }
    }
}

struct RecoveryMetricCompact: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(10)
    }
}
*/
