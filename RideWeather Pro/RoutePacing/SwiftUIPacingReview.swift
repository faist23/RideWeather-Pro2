
//
//  SwiftUIPacingReview.swift
//  Clean SwiftUI implementation for pacing plan review

import SwiftUI

// MARK: - Simple Pacing Plan Review Card

struct SimplePacingReviewCard: View {
    let pacing: PacingPlan
    let strategy: PacingStrategy
    let onViewDetails: () -> Void
    let onRegenerate: () -> Void
    let onExport: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pacing Plan Generated")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Strategy: \(strategy.description)")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Text(pacing.difficulty.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(8)
            }
            
            // Key stats
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Distance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f km", pacing.totalDistance))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatDuration(pacing.totalTimeMinutes * 60))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Avg Power")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(pacing.averagePower))W")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("TSS")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(pacing.estimatedTSS))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            
            // Segment preview
            if !pacing.segments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("First 6 Segments")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(pacing.segments.prefix(6).enumerated()), id: \.offset) { index, segment in
                                SimpleSegmentPreview(segment: segment, index: index)
                            }
                            
                            if pacing.segments.count > 6 {
                                VStack {
                                    Text("+\(pacing.segments.count - 6)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                    Text("more")
                                        .font(.caption2)
                                }
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(.quaternary)
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
            
            // Action buttons
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button("View Full Details") {
                        onViewDetails()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    
                    Button("Export") {
                        onExport()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
                
                Button("Try Different Strategy") {
                    onRegenerate()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct SimpleSegmentPreview: View {
    let segment: PacedSegment
    let index: Int
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(index + 1)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(.blue)
                .clipShape(Circle())
            
            Text("\(Int(segment.targetPower))W")
                .font(.caption2)
                .fontWeight(.medium)
            
            Text(segment.powerZone.name)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            Text(String(format: "%.1fkm", segment.distanceKm))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(6)
        .background(.quaternary)
        .cornerRadius(6)
        .frame(width: 60)
    }
}

// MARK: - Updated Pacing Plan Tab

struct UpdatedPacingPlanTab: View {
    @ObservedObject var viewModel: WeatherViewModel
    @State private var selectedStrategy: PacingStrategy = .balanced
    @State private var showingExport = false
    @State private var showingDetails = false
    @State private var exportText = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // Strategy Selection (always visible)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Select Pacing Strategy")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    ForEach(PacingStrategy.allCases, id: \.self) { strategy in
                        Button(action: {
                            selectedStrategy = strategy
                        }) {
                            HStack {
                                Image(systemName: selectedStrategy == strategy ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedStrategy == strategy ? .blue : .gray)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(strategy.description)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    
                                    Text(descriptionForStrategy(strategy))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                
                                Spacer()
                            }
                            .padding(12)
                            .background(selectedStrategy == strategy ? .blue.opacity(0.1) : .gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button("Generate Pacing Plan") {
                        Task {
                            await viewModel.generateAdvancedCyclingPlan(strategy: selectedStrategy)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(viewModel.isGeneratingAdvancedPlan)
                }
                .padding(16)
                .background(.regularMaterial)
                .cornerRadius(12)
                
                // Loading state
                if viewModel.isGeneratingAdvancedPlan {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Generating pacing plan...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                }
                
                // Error state
                if let error = viewModel.advancedPlanError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundColor(.red)
                        
                        Text("Error")
                            .font(.headline)
                            .foregroundColor(.red)
                        
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Try Again") {
                            Task {
                                await viewModel.generateAdvancedCyclingPlan(strategy: selectedStrategy)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(20)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                }
                
                // Pacing Plan Review (this is what you should see after generation)
                if let controller = viewModel.advancedController,
                   let pacing = controller.pacingPlan,
                   !viewModel.isGeneratingAdvancedPlan {
                    
                    SimplePacingReviewCard(
                        pacing: pacing,
                        strategy: selectedStrategy,
                        onViewDetails: {
                            showingDetails = true
                        },
                        onRegenerate: {
                            Task {
                                await viewModel.generateAdvancedCyclingPlan(strategy: selectedStrategy)
                            }
                        },
                        onExport: {
                            exportText = controller.exportRacePlanCSV()
                            showingExport = true
                        }
                    )
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingExport) {
            ShareSheet(activityItems: [exportText])
        }
        .sheet(isPresented: $showingDetails) {
            if let controller = viewModel.advancedController,
               let pacing = controller.pacingPlan {
                DetailedPacingView(pacing: pacing, controller: controller)
            }
        }
    }
    
    private func descriptionForStrategy(_ strategy: PacingStrategy) -> String {
        switch strategy {
        case .balanced:
            return "Well-rounded approach balancing speed and sustainability"
        case .conservative:
            return "Start easier, maintain energy for later in the ride"
        case .aggressive:
            return "Go hard early, accept some fade later"
        case .negativeSplit:
            return "Build power progressively throughout the ride"
        case .evenEffort:
            return "Adjust for terrain to maintain constant physiological stress"
        }
    }
}

// MARK: - Simple Detailed View

struct DetailedPacingView: View {
    let pacing: PacingPlan
    let controller: AdvancedCyclingController
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // Overview
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Plan Overview")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                            MetricCard(title: "Distance", value: String(format: "%.1f km", pacing.totalDistance), color: .blue)
                            MetricCard(title: "Time", value: formatDuration(pacing.totalTimeMinutes * 60), color: .green)
                            MetricCard(title: "Avg Power", value: "\(Int(pacing.averagePower))W", color: .orange)
                            MetricCard(title: "TSS", value: "\(Int(pacing.estimatedTSS))", color: .red)
                        }
                    }
                    .padding(16)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                    
                    // Power Zones
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Time in Power Zones")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        ForEach(pacing.summary.timeInZones.sorted(by: { $0.key < $1.key }), id: \.key) { zone, minutes in
                            if minutes > 0 {
                                HStack {
                                    Text("Zone \(zone)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    Spacer()
                                    
                                    Text(formatDuration(minutes * 60))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(16)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                    
                    // Segments
                    VStack(alignment: .leading, spacing: 12) {
                        Text("All Segments")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        ForEach(Array(pacing.segments.enumerated()), id: \.offset) { index, segment in
                            HStack {
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(.blue)
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(Int(segment.targetPower))W (\(segment.powerZone.name))")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    Text(String(format: "%.1f km • %.1f min", segment.distanceKm, segment.estimatedTimeMinutes))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(16)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Pacing Plan Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Debug Helper

struct PacingPlanDebugView: View {
    @ObservedObject var viewModel: WeatherViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debug Info:")
                .font(.headline)
            
            Text("Power analysis enabled: \(viewModel.isPowerBasedAnalysisEnabled ? "✅" : "❌")")
            Text("Route points: \(viewModel.routePoints.count)")
            Text("Weather points: \(viewModel.weatherDataForRoute.count)")
            Text("Is generating: \(viewModel.isGeneratingAdvancedPlan ? "✅" : "❌")")
            Text("Has controller: \(viewModel.advancedController != nil ? "✅" : "❌")")
            Text("Has pacing plan: \(viewModel.advancedController?.pacingPlan != nil ? "✅" : "❌")")
            
            if let error = viewModel.advancedPlanError {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(8)
    }
}
