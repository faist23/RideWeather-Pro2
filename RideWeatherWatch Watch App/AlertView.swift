//
//  AlertView.swift
//  RideWeatherWatch Watch App
//
//  Fixed: Explicit colored background based on severity
//

import SwiftUI

struct AlertView: View {
    let alert: WeatherAlert
    
    // Compute background gradient based on severity - transitions to black quickly
    private var backgroundGradient: LinearGradient {
        let baseColor: Color
        switch alert.severity {
        case .severe:
            baseColor = .red
        case .warning:
            baseColor = .orange
        default:
            baseColor = .yellow
        }
        // Gradient that goes to black quickly for better readability
        return LinearGradient(
            colors: [baseColor, baseColor.opacity(0.4), .black],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    var body: some View {
        ZStack {
            // Explicit background layer
            backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 8) {
                
                // Header Group
                VStack(spacing: 4) {
                    // Warning Icon
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse.byLayer, options: .repeating, isActive: true)
                    
                    // Alert Title
                    Text(alert.message.uppercased())
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .layoutPriority(1)
                }
                .padding(.top, 4)
                
                // Full Description
                ScrollView {
                    Text(alert.cleanDescription)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 2)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }
}
