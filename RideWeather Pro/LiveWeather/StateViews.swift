//
//  StateViews.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 8/16/25.
//

import SwiftUI

struct ModernShimmerView: View {
    var body: some View {
        VStack(spacing: 12) {
            // Hero card shimmer
            VStack(spacing: 20) {
                HStack(spacing: 20) {
                    Circle()
                        .fill(.white.opacity(0.3))
                        .frame(width: 80, height: 80)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.3))
                            .frame(width: 120, height: 40)
                        
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.2))
                            .frame(width: 100, height: 20)
                    }
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(spacing: 8) {
                            Circle()
                                .fill(.white.opacity(0.2))
                                .frame(width: 30, height: 30)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(0.2))
                                .frame(height: 16)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .shimmer() // This will now correctly use your Shimmer.swift file
            
            // Additional shimmer cards
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 20)
                    .fill(.thinMaterial)
                    .frame(height: 120)
                    .shimmer() // This will also use your Shimmer.swift file
            }
        }
    }
}

struct ModernErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.yellow)
                .symbolEffect(.bounce)
            
            VStack(spacing: 8) {
                Text("Weather Unavailable")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            
            Button(action: onRetry) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.blue, in: Capsule())
                    .shadow(color: .blue.opacity(0.4), radius: 8, y: 4)
            }
        }
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
    }
}
