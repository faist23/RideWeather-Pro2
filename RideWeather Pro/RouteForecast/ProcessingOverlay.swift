//
//  ProcessingOverlay.swift
//  RideWeather Pro
//
//  Created by Gemini
//

import SwiftUI

struct ProcessingOverlay: View {
    let state: UIState
    
    var body: some View {
        ZStack {
            // 1. Dimmed Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .transition(.opacity)
            
            // 2. Floating "Island" Card
            VStack(spacing: 24) {
                // Dynamic Icon/Progress
                ZStack {
                    if case .parsing(let progress) = state {
                        // Determinate Progress Ring
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 6)
                        
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(.blue.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.smooth, value: progress)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    } else {
                        // Indeterminate Spinner
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    }
                }
                .frame(width: 60, height: 60)
                
                // Status Text
                VStack(spacing: 8) {
                    Text(titleForState)
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Text(subtitleForState)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
            .frame(maxWidth: 280)
            .background(.ultraThinMaterial) // iOS "Glass" effect
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
            .scaleEffect(1.0)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }
    
    private var titleForState: String {
        switch state {
        case .parsing: return "Importing Route"
        case .loading: return "Processing"
        default: return "Working"
        }
    }
    
    private var subtitleForState: String {
        switch state {
        case .parsing: return "Analyzing GPS data and terrain..."
        case .loading: return "Fetching latest weather forecasts..."
        default: return "Please wait a moment"
        }
    }
}

#Preview {
    ZStack {
        Color.blue
        ProcessingOverlay(state: .parsing(0.45))
    }
}