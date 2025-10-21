//
//  FuelingDisplayViews.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 10/1/25.

import Foundation
import SwiftUI
import CoreLocation
import UIKit

struct StrategyOverviewCard: View {
    let fueling: FuelingStrategy
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Strategy Overview")
                    .font(.headline)
                Spacer()
                Text(fueling.strategy.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
            }
            
            if !fueling.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(fueling.recommendations, id: \.self) { rec in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text(rec)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct PrePostRideCards: View {
    let fueling: FuelingStrategy
    
    var body: some View {
        VStack(spacing: 16) {
            // Pre-ride
            VStack(alignment: .leading, spacing: 12) {
                Label("Pre-Ride Fueling", systemImage: "sunrise.fill")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Timing:")
                            .font(.caption.weight(.medium))
                        Text(fueling.preRideFueling.timing)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Amount:")
                            .font(.caption.weight(.medium))
                        Text(fueling.preRideFueling.carbsAmount)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !fueling.preRideFueling.examples.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Examples:")
                            .font(.caption.weight(.medium))
                        ForEach(fueling.preRideFueling.examples, id: \.self) { example in
                            Text("• \(example)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(16)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            
            // Post-ride
            VStack(alignment: .leading, spacing: 12) {
                Label("Post-Ride Recovery", systemImage: "figure.cooldown")
                    .font(.headline)
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Timing:")
                            .font(.caption.weight(.medium))
                        Text(fueling.postRideFueling.timing)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Target:")
                            .font(.caption.weight(.medium))
                        Text("\(fueling.postRideFueling.carbsAmount) + \(fueling.postRideFueling.proteinAmount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !fueling.postRideFueling.examples.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Examples:")
                            .font(.caption.weight(.medium))
                        ForEach(fueling.postRideFueling.examples, id: \.self) { example in
                            Text("• \(example)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(16)
            .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct HydrationCard: View {
    let hydration: HydrationPlan
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Hydration Plan", systemImage: "drop.fill")
                .font(.headline)
                .foregroundColor(.blue)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Fluid")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f L", hydration.totalFluidML / 1000))
                        .font(.title3.weight(.semibold))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Per Hour")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(hydration.fluidPerHourML)) ml/h")
                        .font(.title3.weight(.semibold))
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Schedule:")
                    .font(.caption.weight(.medium))
                Text(hydration.schedule)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if hydration.electrolytesNeeded {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.yellow)
                    Text("Electrolytes recommended for this duration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            
            if !hydration.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(hydration.recommendations, id: \.self) { rec in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text(rec)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
