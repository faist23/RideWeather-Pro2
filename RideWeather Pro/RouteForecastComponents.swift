//
//  ModernProgressView.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/15/25.
//


//
//  RouteForecastComponents.swift
//  RideWeather Pro
//
//  Shared helper views for Route Forecast UI
//

import SwiftUI

// MARK: - Modern Progress View
struct ModernProgressView: View {
    let progress: Double
    let label: String
    
    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 120)
                .tint(.blue)
            
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4)
    }
}

// MARK: - Estimated Time Chip
struct EstimatedTimeChip: View {
    let timeString: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.fill")
                .font(.caption)
                .symbolRenderingMode(.hierarchical)
            
            Text("Estimated: \(timeString)")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4)
    }
}

// MARK: - Modern Loading View
struct ModernLoadingView: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            
            Text("Calculating Weather Forecast...")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4)
    }
}

// MARK: - Error Banner
struct ErrorBanner: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.red.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Import Button
struct ImportButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.arrow.down.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: 50, height: 50)
        .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(.blue)
        .shadow(radius: 2)
    }
}
