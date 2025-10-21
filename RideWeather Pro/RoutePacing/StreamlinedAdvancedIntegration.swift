//
//  StreamlinedAdvancedIntegration.swift
//  RideWeather Pro
//
//  Clean integration using existing PowerRouteAnalyticsEngine

import Foundation
import SwiftUI
import CoreLocation
import UIKit

struct FuelingPlanTab: View {
    @ObservedObject var viewModel: WeatherViewModel
    @State private var showingExport = false
    @State private var exportText = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let controller = viewModel.advancedController,
                   let fueling = controller.fuelingStrategy {
                    RouteInfoCardView(viewModel: viewModel)
                    // Use the components from FuelingDisplayViews.swift
                    StrategyOverviewCard(fueling: fueling)
                    
                    PrePostRideCards(fueling: fueling)
                    
                    // Timeline view with all fuel points
                    VStack(alignment: .leading, spacing: 12) {
                        Text("During Ride Schedule")
                            .font(.headline)
                            .padding(.horizontal, 20)
                        
                        FuelingTimelineView(schedule: Array(fueling.schedule))
                            .padding(.horizontal, 20)
                    }
                    
                    HydrationCard(hydration: fueling.hydration)
                                        
                    // Export button
                    Button("Export Fueling Schedule") {
                        exportText = fueling.exportScheduleAsCSV()
                        showingExport = true
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    
                } else if viewModel.isGeneratingAdvancedPlan {
                    ProgressView("Generating fueling strategy...")
                        .frame(maxWidth: .infinity, maxHeight: 100)
                } else {
                    EmptyStateView(
                        title: "No Fueling Strategy",
                        message: "Generate a pacing plan first to see your personalized fueling strategy",
                        systemImage: "drop"
                    )
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingExport) {
            ShareSheet(activityItems: [exportText])
        }
    }
}

// MARK: - Detailed Pacing Plan View

struct DetailedPacingPlanView: View {
    @ObservedObject var viewModel: WeatherViewModel
    let pacing: PacingPlan
    let controller: AdvancedCyclingController
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSegmentIndex: Int?
    @State private var showingExportOptions = false
    
    var onGoToExportTab: (() -> Void)?

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        RouteInfoCardView(viewModel: viewModel)
                        // Plan overview header
                        PacingPlanHeaderView(pacing: pacing, settings: viewModel.settings, energy: controller.energyExpenditure)

                        // Power zone distribution
                        PowerZoneDistributionView(pacing: pacing)
                        
                        // Key segments highlights - with tap handling
                        if !pacing.summary.keySegments.isEmpty {
                            KeySegmentsView(keySegments: pacing.summary.keySegments) { segmentIndex in
                                withAnimation {
                                    selectedSegmentIndex = segmentIndex
                                    proxy.scrollTo("segment_\(segmentIndex)", anchor: .center)
                                }
                            }
                        }
                        
                        // Warnings if any
                        if !pacing.summary.warnings.isEmpty {
                            WarningsView(warnings: pacing.summary.warnings)
                        }
                        
                        // Segment-by-segment breakdown
                        SegmentBreakdownView(
                            pacing: pacing,
                            selectedIndex: $selectedSegmentIndex,
                            settings: viewModel.settings
                        )
                    }
                    .padding()
                }
            }
            .navigationTitle("Pacing Plan Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Export") {
                        dismiss()
                        onGoToExportTab?()
                    }
                }
            }
            .sheet(isPresented: $showingExportOptions) {
                ExportOptionsView(controller: controller, pacingPlan: pacing)
            }
        }
    }
}

struct PacingPlanHeaderView: View {
    let pacing: PacingPlan
    let settings: AppSettings
    let energy: EnergyExpenditure?  // Add this parameter

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pacing Plan Summary")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Strategy: \(pacing.strategy.description)")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    
                    Text("Difficulty: \(pacing.difficulty.rawValue)")
                        .font(.subheadline)
                        .foregroundColor(Color(hex: pacing.difficulty.color))
                }
                
                Spacer()
            }
            
            // Key metrics grid - Now 6 items (3x2 grid)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                HeaderMetricCard(
                    title: "Total Distance",
                    value: formatDistance(pacing.totalDistance),
                    icon: "road.lanes",
                    color: .blue
                )
                
                HeaderMetricCard(
                    title: "Estimated Time",
                    value: formatDuration(pacing.totalTimeMinutes * 60),
                    icon: "clock",
                    color: .green
                )
                
                HeaderMetricCard(
                    title: "Avg Speed",
                    value: formatSpeed(pacing.totalDistance, pacing.totalTimeMinutes),
                    icon: "speedometer",
                    color: .purple
                )
                
                // Normalized power display
                VStack(spacing: 8) {
                    Image(systemName: "bolt")
                        .font(.title2)
                        .foregroundColor(.orange)
                    
                    Text("Norm Power")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    VStack(spacing: 2) {
                        Text("\(Int(pacing.normalizedPower)) W")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("(avg \(Int(pacing.averagePower)) W)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                
                // Intensity factor
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                    
                    Text("Intensity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    VStack(spacing: 2) {
                        Text("IF \(String(format: "%.2f", pacing.intensityFactor))")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("\(Int(pacing.estimatedTSS)) TSS")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                
                // Add energy burned
                if let energy = energy {
                    HeaderMetricCard(
                        title: "Energy Burned",
                        value: "\(Int(energy.totalCalories)) kcal",
                        icon: "flame.fill",
                        color: .pink
                    )
                } else {
                    // Placeholder if energy data isn't available
                    VStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                        
                        Text("Energy")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("N/A")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
        
    private func formatSpeed(_ distanceKm: Double, _ timeMinutes: Double) -> String {
        let timeHours = timeMinutes / 60.0
        let speedKph = distanceKm / timeHours
        
        if settings.units == .metric {
            return String(format: "%.1f km/h", speedKph)
        } else {
            let speedMph = speedKph * 0.621371
            return String(format: "%.1f mph", speedMph)
        }
    }
    
    private func formatDistance(_ distanceKm: Double) -> String {
        if settings.units == .metric {
            return String(format: "%.1f km", distanceKm)
        } else {
            let miles = distanceKm * 0.621371
            return String(format: "%.1f mi", miles)
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)min"
        } else {
            return "\(minutes)min"
        }
    }
}

struct HeaderMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
        }
        .padding(16)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PowerZoneDistributionView: View {
    let pacing: PacingPlan
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Time in Power Zones")
                .font(.headline)
                .fontWeight(.semibold)
            
            ForEach(pacing.summary.timeInZones.sorted(by: { $0.key < $1.key }), id: \.key) { zone, minutes in
                if minutes > 0 {
                    let zoneName = PowerZone.zones(for: pacing.averagePower)[safe: zone - 1]?.name ?? "Zone \(zone)"
                    let zoneColor = PowerZone.zones(for: pacing.averagePower)[safe: zone - 1]?.color ?? "#9E9E9E"
                    
                    PowerZoneRow(
                        zoneName: zoneName,
                        zoneColor: Color(hex: zoneColor),
                        minutes: minutes,
                        totalMinutes: pacing.totalTimeMinutes
                    )
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct PowerZoneRow: View {
    let zoneName: String
    let zoneColor: Color
    let minutes: Double
    let totalMinutes: Double
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(zoneColor)
                    .frame(width: 12, height: 12)
                
                Text(zoneName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(formatDuration(minutes * 60))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Text("(\(Int((minutes / totalMinutes) * 100))%)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 6)
                    
                    Rectangle()
                        .fill(zoneColor)
                        .frame(width: geometry.size.width * (minutes / totalMinutes), height: 6)
                }
            }
            .frame(height: 6)
            .cornerRadius(3)
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)min"
        } else {
            return "\(minutes)min"
        }
    }
}

struct SegmentBreakdownView: View {
    let pacing: PacingPlan
    @Binding var selectedIndex: Int?
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Segment Breakdown")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVStack(spacing: 8) {
                ForEach(Array(pacing.segments.enumerated()), id: \.offset) { index, segment in
                    SegmentDetailRow(
                        segment: segment,
                        index: index,
                        distanceMarker: cumulativeDistanceMarker(upTo: index),
                        isSelected: selectedIndex == index,
                        settings: settings
                    ) {
                        withAnimation {
                            selectedIndex = selectedIndex == index ? nil : index
                        }
                    }
                    .id("segment_\(index)")
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    private func cumulativeDistanceMarker(upTo index: Int) -> String {
        // Calculate distance UP TO (but not including) this segment
        let cumulativeKm = pacing.segments.prefix(index).reduce(0.0) { $0 + $1.distanceKm }
        
        if settings.units == .metric {
            return String(format: "%.1f km", cumulativeKm)
        } else {
            let miles = cumulativeKm * 0.621371
            return String(format: "%.1f mi", miles)
        }
    }
}

struct SegmentDetailRow: View {
    let segment: PacedSegment
    let index: Int
    let distanceMarker: String
    let isSelected: Bool
    let settings: AppSettings
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // Segment number badge
                    Text("\(index + 1)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color(hex: segment.powerZone.color), in: Circle())
                    
                    // Segment overview
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(Int(segment.targetPower))W")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Text("(\(segment.powerZone.name))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            // Distance marker - shows cumulative distance
                            Text(distanceMarker)
                                .font(.caption)
                                .foregroundColor(.blue)
                                .fontWeight(.medium)
                        }
                        
                        Text(segment.strategy)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(isSelected ? Color(hex: segment.powerZone.color).opacity(0.1) : .clear)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            // Expanded details
            if isSelected {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 9) {
                        DetailMetric(title: "Time", value: String(format: "%.1f min", segment.estimatedTimeMinutes))
                        DetailMetric(title: "Distance", value: formatDistance(segment.distanceKm))
                        DetailMetric(title: "Speed", value: formattedSpeed())
                        DetailMetric(title: "Grade", value: String(format: "%.1f%%", segment.originalSegment.elevationGrade * 100))
                        DetailMetric(title: "TSS", value: String(format: "%.0f", segment.cumulativeStress))
                    }
                    
                    // ✅ CHANGED: Logic to handle both headwind and tailwind
                    let windMps = segment.originalSegment.averageHeadwindMps
                    
                    if windMps > 1 { // Significant headwind
                        HStack {
                            Image(systemName: "wind")
                                .foregroundColor(.blue)
                            Text("Headwind: \(formattedWindSpeed(windMps: windMps))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if windMps < -1 { // Significant tailwind
                        HStack {
                            Image(systemName: "wind.circle.fill")
                                .foregroundColor(.green)
                            Text("Tailwind: \(formattedWindSpeed(windMps: windMps))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.asymmetric(insertion: .opacity, removal: .opacity))
            }
        }
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
    
    // ✅ ADDED: Helper function to calculate and format segment speed
    private func formattedSpeed() -> String {
        guard segment.estimatedTimeMinutes > 0 else { return "N/A" }
        let speedKph = segment.distanceKm / (segment.estimatedTimeMinutes / 60.0)
        
        if settings.units == .metric {
            return String(format: "%.1f kph", speedKph)
        } else {
            let speedMph = speedKph * 0.621371
            return String(format: "%.1f mph", speedMph)
        }
    }
    
    // ✅ ADDED: Helper function to format distance for consistency
    private func formatDistance(_ distanceKm: Double) -> String {
        if settings.units == .metric {
            return String(format: "%.2f km", distanceKm)
        } else {
            let miles = distanceKm * 0.621371
            return String(format: "%.2f mi", miles)
        }
    }
    
    // ✅ CHANGED: Renamed from formattedHeadwindSpeed to be more generic
    private func formattedWindSpeed(windMps: Double) -> String {
        let absWindMps = abs(windMps)
        let unitSystem = settings.units
        
        if unitSystem == .metric {
            let windKph = absWindMps * 3.6
            return String(format: "%.1f kph", windKph)
        } else {
            let windMph = absWindMps * 2.23694
            return String(format: "%.1f mph", windMph)
        }
    }
}

struct DetailMetric: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

struct KeySegmentsView: View {
    let keySegments: [KeySegment]
    let onSegmentTap: (Int) -> Void  // NEW callback

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Key Segments")
                .font(.headline)
                .fontWeight(.semibold)
            
            ForEach(keySegments, id: \.segmentIndex) { keySegment in
                KeySegmentCard(keySegment: keySegment, onTap: {
                    onSegmentTap(keySegment.segmentIndex)  // NEW
                })
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct KeySegmentCard: View {
    let keySegment: KeySegment
    let onTap: () -> Void  // NEW
    
    var body: some View {
        Button(action: onTap) {  // NEW - wrapped in Button
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconForSegmentType(keySegment.type))
                    .font(.title2)
                    .foregroundColor(colorForSegmentType(keySegment.type))
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Segment \(keySegment.segmentIndex + 1): \(keySegment.description)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(keySegment.recommendation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(colorForSegmentType(keySegment.type).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)  // NEW
    }
    
    private func iconForSegmentType(_ type: KeySegmentType) -> String {
        switch type {
        case .majorClimb: return "mountain.2.fill"
        case .highIntensity: return "bolt.fill"
        case .fuelOpportunity: return "drop.fill"
        case .technicalSection: return "exclamationmark.triangle.fill"
        case .recovery: return "leaf.fill"
        }
    }
    
    private func colorForSegmentType(_ type: KeySegmentType) -> Color {
        switch type {
        case .majorClimb: return .orange
        case .highIntensity: return .red
        case .fuelOpportunity: return .blue
        case .technicalSection: return .yellow
        case .recovery: return .green
        }
    }
}

struct WarningsView: View {
    let warnings: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Important Notes")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
            
            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                    
                    Text(warning)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

struct ExportOptionsView: View {
    let controller: AdvancedCyclingController
    let pacingPlan: PacingPlan // <-- Add this property
    @Environment(\.dismiss) private var dismiss
    @State private var exportText = ""
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Button("Export as CSV") {
                    exportText = controller.exportPacingPlanCSV(using: pacingPlan)
                    showingShareSheet = true
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                
                Button("Generate Race Day Summary") {
                    exportText = controller.generateRaceDaySummary(using: pacingPlan)
                    showingShareSheet = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: [exportText])
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundColor(.gray)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Reusable Shared UI Components

struct RouteInfoCardView: View {
    // This view takes the viewModel to get the data it needs.
    @ObservedObject var viewModel: WeatherViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "map.fill")
                    .foregroundStyle(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Route")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(viewModel.routeDisplayName)
                        .font(.body)
                        .fontWeight(.semibold)
                }
                
                Spacer()
            }
            
            if let fileName = viewModel.lastImportedFileName, !fileName.isEmpty {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    
                    Text("Source: \(fileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

