//
//  ProcessingOverlay.swift
//  RideWeather Pro
//
//  Created by Gemini
//

import SwiftUI

struct ProcessingOverlay: View {
    var message: String = "Processing..."
    var progress: Double? = nil // If nil, shows spinning indicator. If set (0.0-1.0), shows pie.
    
    var body: some View {
        ZStack {
            // 1. Dimmed Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .transition(.opacity)
            
            // 2. Glassmorphism Card
            VStack(spacing: 20) {
                ZStack {
                    if let progress = progress {
                        // Determinate Progress Ring
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 6)
                            .frame(width: 50, height: 50)
                        
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(.blue.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 50, height: 50)
                            .rotationEffect(.degrees(-90))
                            .animation(.smooth, value: progress)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    } else {
                        // Indeterminate Spinner
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    }
                }
                
                VStack(spacing: 8) {
                    Text(titleForState)
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(30)
            .frame(maxWidth: 260)
            .background(.ultraThinMaterial) // The "Glass" effect
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        }
        .zIndex(100) // Ensure it sits on top of everything
    }
    
    private var titleForState: String {
        if progress != nil { return "Importing Route" }
        return "Working"
    }
}

#Preview {
    ZStack {
        Color.blue
        ProcessingOverlay(message: "Analyzing terrain data...", progress: 0.85)
    }
}
