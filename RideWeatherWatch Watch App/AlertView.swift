//
//  AlertView.swift
//  RideWeatherWatch Watch App
//
//  Fixed: Reverted to WHITE text for the main Alert Page.
//

import SwiftUI

struct AlertView: View {
    let alert: WeatherAlert
    
    // Dynamic Background Gradient
    private var backgroundColor: Color {
        switch alert.severity {
        case .severe: return .red
        case .warning: return .orange
        default: return .yellow
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            
            // Header Group
            VStack(spacing: 4) {
                // Warning Icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white) // Fixed: Back to White
                    .symbolEffect(.pulse.byLayer, options: .repeating, isActive: true)
                
                // Alert Title
                Text(alert.message.uppercased())
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white) // Fixed: Back to White
                    .multilineTextAlignment(.center)
                    .layoutPriority(1)
            }
            .padding(.top, 4)
            
            // Full Description
            ScrollView {
                Text(alert.cleanDescription)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95)) // Fixed: Back to White
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .containerBackground(backgroundColor.gradient, for: .tabView)
    }
}
