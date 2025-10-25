//
// RideAnalysisView.swift
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

// MARK: - Main Analysis View

struct RideAnalysisView: View {
    @StateObject private var viewModel = RideAnalysisViewModel()
    @ObservedObject var weatherViewModel: WeatherViewModel
    @EnvironmentObject var stravaService: StravaService

    var body: some View {
        NavigationView {
            Group {
                if viewModel.currentAnalysis == nil {
                    emptyStateView
                } else {
                    analysisResultsView
                }
            }
            .navigationTitle("Ride Analysis")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { viewModel.showingHistory = true }) {
                            Label("View History", systemImage: "clock")
                        }
                        Button(action: { viewModel.showingFilePicker = true }) {
                            Label("Import FIT File", systemImage: "square.and.arrow.down")
                        }
                        if stravaService.isAuthenticated {
                                 Button(action: { viewModel.showingStravaActivities = true }) {
                                     Label("Import from Strava", systemImage: "square.and.arrow.down.on.square")
                                 }
                             }
         
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .fileImporter(
                isPresented: $viewModel.showingFilePicker,
                allowedContentTypes: [.init(filenameExtension: "fit")!],
                allowsMultipleSelection: false
            ) { result in
                viewModel.handleFileImport(
                    result: result,
                    ftp: weatherViewModel.settings.functionalThresholdPower,
                    weight: weatherViewModel.settings.bodyWeight
                )
            }
            .sheet(isPresented: $viewModel.showingHistory) {
                RideHistoryView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showingExportOptions) {
                if let analysis = viewModel.currentAnalysis {
                    RideAnalysisExportView(analysis: analysis)
                }
            }
            .sheet(item: $viewModel.shareItem) { item in
                ShareSheet(activityItems: [item.url])
            }
            // ✅ ADD THIS - Strava activities sheet
            .sheet(isPresented: $viewModel.showingStravaActivities) {
                StravaActivitiesView()
                    .environmentObject(stravaService)
                    .environmentObject(weatherViewModel)
            }
            // ✅ ADD THIS - Listen for Strava imports
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewAnalysisImported"))) { notification in
                if let analysis = notification.object as? RideAnalysis {
                    viewModel.currentAnalysis = analysis
                    viewModel.loadHistory()
                    // ✅ The .onChange modifier above will handle the scroll automatically
                }
            }
        }
    }
 
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            Text("No Ride Analysis Yet")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Import a FIT file from your bike computer to analyze your ride performance")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: { viewModel.showingFilePicker = true }) {
                Label("Import FIT File", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            
            // ✅ ADD THIS - Strava import button
            if stravaService.isAuthenticated {
                Button(action: { viewModel.showingStravaActivities = true }) {
                    HStack(spacing: 12) {
                        Image("strava_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 20)
                        Text("Import from Strava")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
            }
            
            if !viewModel.analysisHistory.isEmpty {
                Button(action: { viewModel.showingHistory = true }) {
                    Label("View Past Analyses", systemImage: "clock")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
        }
        .overlay {
            if viewModel.isAnalyzing {
                analyzingOverlay
            }
        }
    }
    
    private var analyzingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                Text("Analyzing Ride...")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(viewModel.analysisStatus)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
            )
        }
    }
    
    // MARK: - Analysis Results
    
    private var analysisResultsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    if let analysis = viewModel.currentAnalysis {
                        // Add an ID to the first element
                        RideMetadataCard(analysis: analysis, useMetric: weatherViewModel.settings.units == .metric)
                            .id("top")  // ✅ ADD THIS
                        
                        // Performance Score Card
                        PerformanceScoreCard(analysis: analysis)
                        
                        // NEW: Power Allocation Card (critical!)
                        if analysis.powerAllocation != nil {
                            PowerAllocationCard(analysis: analysis)
                        }
                        
                        // NEW: Terrain Segments
                        if let segments = analysis.terrainSegments, !segments.isEmpty {
                            TerrainSegmentsCard(analysis: analysis)
                        }
                        
                        // Quick Stats
                        QuickStatsCard(analysis: analysis, useMetric: weatherViewModel.settings.units == .metric)
                        
                        // Power Metrics Card
                        PowerMetricsCard(analysis: analysis)
                        
                        // Pacing Analysis Card
                        PacingAnalysisCard(analysis: analysis)
                        
                        // Power Zone Distribution
                        PowerZoneDistributionCard(analysis: analysis)
                        
                        // Segment Comparison (if available)
                        if !analysis.segmentComparisons.isEmpty {
                            SegmentComparisonCard(analysis: analysis)
                        }
                        
                        // Insights Cards (now much smarter!)
                        InsightsSection(insights: analysis.insights)
                        
                        // Export Options
                        ExportButtonsCard(
                            onExportCSV: { viewModel.exportCSV(analysis) },
                            onExportReport: { viewModel.exportReport(analysis) }
                        )
                    }
                }
                .padding()
            }
            // ✅ ADD THIS: Scroll to top when analysis changes
            .onChange(of: viewModel.currentAnalysis?.id) { oldValue, newValue in
                if newValue != nil && oldValue != newValue {
                    withAnimation {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
            }
        }
    }
}

// MARK: - Performance Score Card

struct PerformanceScoreCard: View {
    let analysis: RideAnalysis
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Performance Score")
                .font(.headline)
            
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                
                Circle()
                    .trim(from: 0, to: analysis.performanceScore / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.0, dampingFraction: 0.8), value: analysis.performanceScore)
                
                VStack(spacing: 4) {
                    Text("\(Int(analysis.performanceScore))")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor)
                    
                    Text("out of 100")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 200, height: 200)
            
            Text(scoreDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var scoreColor: Color {
        switch analysis.performanceScore {
        case 85...100: return .green
        case 70..<85: return .blue
        case 50..<70: return .orange
        default: return .red
        }
    }
    
    private var scoreDescription: String {
        switch analysis.performanceScore {
        case 85...100: return "Outstanding execution! Race-ready performance."
        case 70..<85: return "Solid performance with room for improvement."
        case 50..<70: return "Good effort, but pacing needs refinement."
        default: return "Significant pacing issues detected."
        }
    }
}

// MARK: - Quick Stats Card

struct QuickStatsCard: View {
    let analysis: RideAnalysis
    let useMetric: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ride Summary")
                .font(.headline)
            
            HStack(spacing: 16) {
                StatItem(
                    icon: "clock",
                    label: "Duration",
                    value: analysis.formattedDuration
                )
                
                Divider()
                
                StatItem(
                    icon: "figure.outdoor.cycle",
                    label: "Distance",
                    value: useMetric ? analysis.formattedDistance : analysis.formattedDistanceMiles
                )
                
                Divider()
                
                StatItem(
                    icon: "bolt",
                    label: "Avg Power",
                    value: "\(Int(analysis.averagePower))W"
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Ride Metadata Card

// MARK: - 🔥 FIXED Ride Metadata Card

struct RideMetadataCard: View {
    let analysis: RideAnalysis
    let useMetric: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(analysis.rideName)
                .font(.title2)
                .fontWeight(.bold)
            
            if let metadata = analysis.metadata {
                VStack(alignment: .leading, spacing: 16) {
                    // 🔥 DATE & TIME SECTION
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Date")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(metadata.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    
                    Divider()
                    
                    // 🔥 DURATION BREAKDOWN (The Critical Fix!)
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Moving Time")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatDuration(metadata.movingTime))
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Elapsed Time")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatDuration(metadata.totalTime))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        
                        if metadata.stoppedTime > 60 {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Stopped")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatDuration(metadata.stoppedTime))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    
                    // 🔥 SHOW PERCENTAGE IF SIGNIFICANT STOP TIME
                    if metadata.stoppedTime > 60 {
                        let stoppedPct = (metadata.stoppedTime / metadata.totalTime) * 100
                        HStack(spacing: 8) {
                            Image(systemName: stoppedPct > 15 ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                .foregroundColor(stoppedPct > 15 ? .orange : .blue)
                                .font(.caption)
                            Text("Stopped for \(Int(stoppedPct))% of ride")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Divider()
                    
                    // 🔥 ELEVATION & GRADIENT
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Elevation Gain")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                Text(formatElevation(metadata.elevationGain, useMetric: useMetric))
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        }
                        
                        if metadata.maxGradient > 5 {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Max Grade")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(String(format: "%.1f", metadata.maxGradient))%")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", secs))"
        } else {
            return "\(minutes):\(String(format: "%02d", secs))"
        }
    }
    
    private func formatElevation(_ meters: Double, useMetric: Bool) -> String {
        if useMetric {
            return "\(Int(meters))m"
        } else {
            let feet = meters * 3.28084
            return "\(Int(feet))ft"
        }
    }
}

private var cardBackground: some View {
    Color(.systemBackground)
}

// MARK: - Terrain Segments Card

struct TerrainSegmentsCard: View {
    let analysis: RideAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Power by Terrain")
                .font(.headline)
            
            if let segments = analysis.terrainSegments, !segments.isEmpty {
                VStack(spacing: 12) {
                    ForEach(segments.filter { $0.duration > 30 }.prefix(8)) { segment in
                        TerrainSegmentRow(segment: segment)
                    }
                }
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct TerrainSegmentRow: View {
    let segment: TerrainSegment
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(segment.type.emoji)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(segment.type.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if segment.type == .climb || segment.type == .rolling {
                    Text("\(String(format: "%.1f%%", segment.gradient)) grade")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(segment.averagePower))W")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(efficiencyColor(segment.powerEfficiency))
                
                Text("\(Int(segment.powerEfficiency))% optimal")
                    .font(.caption)
                    .foregroundColor(efficiencyColor(segment.powerEfficiency))
            }
        }
        .padding(.vertical, 4)
    }
    
    private func efficiencyColor(_ efficiency: Double) -> Color {
        if efficiency >= 90 { return .green }
        if efficiency >= 75 { return .blue }
        if efficiency >= 60 { return .orange }
        return .red
    }
}

// MARK: - Power Allocation Card

struct PowerAllocationCard: View {
    let analysis: RideAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Power Distribution Analysis")
                .font(.headline)
            
            if let allocation = analysis.powerAllocation {
                VStack(spacing: 16) {
                    // Efficiency Score
                    HStack {
                        Text("Allocation Efficiency")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(allocation.allocationEfficiency))%")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(efficiencyColor(allocation.allocationEfficiency))
                    }
                    
                    // Time savings potential
                    if allocation.estimatedTimeSaved > 5 {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading) {
                                Text("Potential Time Savings")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("~\(formatTimeSaved(allocation.estimatedTimeSaved))")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Divider()
                    
                    // Power breakdown
                    Text("Where Your Watts Went")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    PowerBreakdownBar(
                        climbWatts: allocation.wattsUsedOnClimbs,
                        flatWatts: allocation.wattsUsedOnFlats,
                        descentWatts: allocation.wattsUsedOnDescents,
                        totalWatts: allocation.totalWatts
                    )
                }
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private func efficiencyColor(_ efficiency: Double) -> Color {
        if efficiency >= 90 { return .green }
        if efficiency >= 75 { return .blue }
        if efficiency >= 60 { return .orange }
        return .red
    }
    
    private func formatTimeSaved(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}

struct PowerBreakdownBar: View {
    let climbWatts: Double
    let flatWatts: Double
    let descentWatts: Double
    let totalWatts: Double
    
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: geometry.size.width * (climbWatts / totalWatts))
                    
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * (flatWatts / totalWatts))
                    
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geometry.size.width * (descentWatts / totalWatts))
                }
            }
            .frame(height: 30)
            .cornerRadius(6)
            
            HStack(spacing: 16) {
                LegendItem(color: .red, label: "Climbs", percentage: (climbWatts / totalWatts) * 100)
                LegendItem(color: .blue, label: "Flats", percentage: (flatWatts / totalWatts) * 100)
                LegendItem(color: .green, label: "Descents", percentage: (descentWatts / totalWatts) * 100)
            }
            .font(.caption)
        }
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    let percentage: Double
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(label) \(Int(percentage))%")
                .foregroundColor(.secondary)
        }
    }
}

struct StatItem: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.headline)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Power Metrics Card

struct PowerMetricsCard: View {
    let analysis: RideAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Power Metrics")
                .font(.headline)
            
            VStack(spacing: 12) {
                MetricRow(label: "Normalized Power (NP)", value: "\(Int(analysis.normalizedPower))W")
                MetricRow(label: "Intensity Factor (IF)", value: String(format: "%.2f", analysis.intensityFactor))
                MetricRow(label: "Training Stress Score (TSS)", value: "\(Int(analysis.trainingStressScore))")
                MetricRow(label: "Variability Index (VI)", value: String(format: "%.2f", analysis.variabilityIndex))
            }
            
            Divider()
            
            Text("Peak Powers")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                PeakPowerRow(duration: "5 seconds", power: Int(analysis.peakPower5s))
                PeakPowerRow(duration: "1 minute", power: Int(analysis.peakPower1min))
                PeakPowerRow(duration: "5 minutes", power: Int(analysis.peakPower5min))
                PeakPowerRow(duration: "20 minutes", power: Int(analysis.peakPower20min))
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

struct PeakPowerRow: View {
    let duration: String
    let power: Int
    
    var body: some View {
        HStack {
            Text(duration)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(power)W")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
        }
    }
}

// MARK: - Pacing Analysis Card

struct PacingAnalysisCard: View {
    let analysis: RideAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pacing Analysis")
                .font(.headline)
            
            HStack(spacing: 20) {
                // Consistency Gauge
                VStack {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                        
                        Circle()
                            .trim(from: 0, to: analysis.consistencyScore / 100)
                            .stroke(consistencyColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        
                        Text("\(Int(analysis.consistencyScore))%")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    .frame(width: 80, height: 80)
                    
                    Text("Consistency")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("Rating: \(analysis.pacingRating.rawValue)", systemImage: "star.fill")
                        .font(.subheadline)
                        .foregroundColor(consistencyColor)
                    
                    Label("Variability: \(String(format: "%.1f", analysis.powerVariability))%",
                          systemImage: "waveform.path.ecg")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Label("Surges: \(analysis.surgeCount)", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline)
                        .foregroundColor(analysis.surgeCount > 10 ? .orange : .green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if analysis.fatigueDetected, let onset = analysis.fatigueOnsetTime {
                Divider()
                
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading) {
                        Text("Fatigue Detected")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Power declined after \(Int(onset / 60)) minutes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var consistencyColor: Color {
        switch analysis.consistencyScore {
        case 85...100: return .green
        case 70..<85: return .blue
        case 50..<70: return .orange
        default: return .red
        }
    }
}

// MARK: - Power Zone Distribution Card

struct PowerZoneDistributionCard: View {
    let analysis: RideAnalysis
    
    private let zoneColors: [Color] = [.gray, .blue, .green, .yellow, .orange, .red, .purple]
    private let zoneNames = ["Z1: Recovery", "Z2: Endurance", "Z3: Tempo", "Z4: Sweet Spot",
                            "Z5: Threshold", "Z6: VO2 Max", "Z7: Anaerobic"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Power Zone Distribution")
                .font(.headline)
            
            // Zone bars
            VStack(spacing: 8) {
                ForEach(1...7, id: \.self) { zone in
                    ZoneBar(
                        zoneName: zoneNames[zone - 1],
                        percentage: analysis.powerZoneDistribution.percentage(for: zone, totalTime: analysis.duration),
                        color: zoneColors[zone - 1]
                    )
                }
            }
            
            Text("Time in each power zone based on FTP")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct ZoneBar: View {
    let zoneName: String
    let percentage: Double
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Text(zoneName)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 20)
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * (percentage / 100), height: 20)
                }
                .cornerRadius(4)
            }
            .frame(height: 20)
            
            Text(String(format: "%.0f%%", percentage))
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - Segment Comparison Card

struct SegmentComparisonCard: View {
    let analysis: RideAnalysis
    @State private var expandedSegment: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Segment Comparison")
                    .font(.headline)
                
                Spacer()
                
                Text("Overall: \(String(format: "%.1f%%", analysis.overallDeviation)) deviation")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                ForEach(analysis.segmentComparisons) { segment in
                    SegmentComparisonRow(
                        segment: segment,
                        isExpanded: expandedSegment == segment.id
                    )
                    .onTapGesture {
                        withAnimation {
                            expandedSegment = expandedSegment == segment.id ? nil : segment.id
                        }
                    }
                }
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct SegmentComparisonRow: View {
    let segment: SegmentComparison
    let isExpanded: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                
                Text(segment.segmentName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(segment.deviation > 0 ? "+" : "")\(String(format: "%.1f%%", segment.deviation))")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(statusColor)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            
            if isExpanded {
                VStack(spacing: 8) {
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Planned")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(segment.plannedPower))W")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("Actual")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(segment.actualPower))W")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(statusColor)
                        }
                    }
                    
                    HStack {
                        Text("Time:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatTime(segment.actualTime))
                            .font(.caption)
                        
                        Spacer()
                        
                        let timeDiff = segment.timeDifference
                        if abs(timeDiff) > 1 {
                            Text(timeDiff > 0 ? "+\(formatTime(timeDiff))" : "-\(formatTime(abs(timeDiff)))")
                                .font(.caption)
                                .foregroundColor(timeDiff > 0 ? .red : .green)
                        }
                    }
                }
                .padding(.leading)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var statusIcon: String {
        switch segment.deviationStatus {
        case .onTarget: return "checkmark.circle.fill"
        case .tooHard: return "arrow.up.circle.fill"
        case .tooEasy: return "arrow.down.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch segment.deviationStatus {
        case .onTarget: return .green
        case .tooHard: return .red
        case .tooEasy: return .orange
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Insights Section

struct InsightsSection: View {
    let insights: [RideInsight]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insights & Recommendations")
                .font(.headline)
            
            ForEach(insights) { insight in
                InsightCard(insight: insight)
            }
        }
    }
}

struct InsightCard: View {
    let insight: RideInsight
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: priorityIcon)
                .font(.title3)
                .foregroundColor(priorityColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(insight.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text(insight.priority.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(priorityColor)
                        .cornerRadius(6)
                }
                
                Text(insight.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    
                    Text(insight.recommendation)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                .padding(8)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var priorityIcon: String {
        switch insight.priority {
        case .high: return "exclamationmark.triangle.fill"
        case .medium: return "info.circle.fill"
        case .low: return "checkmark.circle.fill"
        }
    }
    
    private var priorityColor: Color {
        switch insight.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }
}

// MARK: - Export Buttons Card

struct ExportButtonsCard: View {
    let onExportCSV: () -> Void
    let onExportReport: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: onExportCSV) {
                HStack {
                    Image(systemName: "tablecells")
                    Text("Export to CSV")
                    Spacer()
                    Image(systemName: "arrow.down.doc")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            
            Button(action: onExportReport) {
                HStack {
                    Image(systemName: "doc.text")
                    Text("Export Full Report")
                    Spacer()
                    Image(systemName: "arrow.down.doc")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding()
                .background(Color.green)
                .cornerRadius(12)
            }
        }
    }
}

// MARK: - Ride History View

struct RideHistoryView: View {
    @ObservedObject var viewModel: RideAnalysisViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.analysisHistory.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "clock")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No History Yet")
                            .font(.title2)
                            .padding()
                        Spacer()
                    }
                } else {
                    List {
                        Section {
                            TrendChartView(trendData: viewModel.getTrendData())
                                .frame(height: 200)
                                .listRowInsets(EdgeInsets())
                        }
                        
                        Section(header: Text("Past Analyses")) {
                            ForEach(viewModel.analysisHistory) { analysis in
                                HistoryRow(analysis: analysis)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.selectAnalysis(analysis)
                                        dismiss()
                                    }
                            }
                            .onDelete { indexSet in
                                viewModel.deleteAnalyses(at: indexSet)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ride History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                if !viewModel.analysisHistory.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { viewModel.exportAllHistory() }) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }
}

struct HistoryRow: View {
    let analysis: RideAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(analysis.rideName)
                    .font(.headline)
                
                Spacer()
                
                Text("\(Int(analysis.performanceScore))")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(scoreColor)
            }
            
            HStack {
                Label(analysis.formattedDuration, systemImage: "clock")
                    .font(.caption)
                
                Label(analysis.formattedDistance, systemImage: "figure.outdoor.cycle")
                    .font(.caption)
                
                Label("\(Int(analysis.normalizedPower))W", systemImage: "bolt")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            
            Text(analysis.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var scoreColor: Color {
        switch analysis.performanceScore {
        case 85...100: return .green
        case 70..<85: return .blue
        case 50..<70: return .orange
        default: return .red
        }
    }
}

// MARK: - Trend Chart View

struct TrendChartView: View {
    let trendData: [TrendDataPoint]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance Trend")
                .font(.headline)
                .padding(.horizontal)
            
            GeometryReader { geometry in
                ZStack {
                    // Grid lines
                    Path { path in
                        for i in 0...4 {
                            let y = geometry.size.height * CGFloat(i) / 4
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                    }
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    
                    // Performance score line
                    if !trendData.isEmpty {
                        Path { path in
                            let points = trendData.enumerated().map { index, data in
                                CGPoint(
                                    x: CGFloat(index) * (geometry.size.width / CGFloat(max(trendData.count - 1, 1))),
                                    y: geometry.size.height * (1 - CGFloat(data.performanceScore / 100))
                                )
                            }
                            
                            if let first = points.first {
                                path.move(to: first)
                                for point in points.dropFirst() {
                                    path.addLine(to: point)
                                }
                            }
                        }
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        
                        // Data points
                        ForEach(trendData.indices, id: \.self) { index in
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                                .position(
                                    x: CGFloat(index) * (geometry.size.width / CGFloat(max(trendData.count - 1, 1))),
                                    y: geometry.size.height * (1 - CGFloat(trendData[index].performanceScore / 100))
                                )
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(.systemGray6))
    }
}

// MARK: - Ride Analysis Share Sheet View (Renamed to avoid conflict)

struct RideAnalysisExportView: View {
    let analysis: RideAnalysis
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Export Format")) {
                    Button(action: { exportCSV() }) {
                        HStack {
                            Image(systemName: "tablecells")
                            Text("CSV Spreadsheet")
                            Spacer()
                            Image(systemName: "arrow.down.doc")
                        }
                    }
                    
                    Button(action: { exportReport() }) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Text Report")
                            Spacer()
                            Image(systemName: "arrow.down.doc")
                        }
                    }
                }
            }
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
    }
    
    private func exportCSV() {
        let csv = analysis.exportToCSV()
        shareText(csv, filename: "ride-analysis.csv")
    }
    
    private func exportReport() {
        let report = analysis.exportToReport()
        shareText(report, filename: "ride-report.txt")
    }
    
    private func shareText(_ text: String, filename: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try text.write(to: tempURL, atomically: true, encoding: .utf8)
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            print("Export error: \(error)")
        }
    }
}

// MARK: - View Model

@MainActor
class RideAnalysisViewModel: ObservableObject {
    @Published var currentAnalysis: RideAnalysis?
    @Published var analysisHistory: [RideAnalysis] = []
    @Published var isAnalyzing = false
    @Published var analysisStatus = ""
    @Published var showingFilePicker = false
    @Published var showingHistory = false
    @Published var showingExportOptions = false
    @Published var shareItem: ShareItem?
    @Published var showingStravaActivities = false

    private let analyzer = RideFileAnalyzer()
    private let parser = FITFileParser()
    private let storage = AnalysisStorageManager()
    
    init() {
        loadHistory()
    }
    
    func handleFileImport(result: Result<[URL], Error>, ftp: Int, weight: Double) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            analyzeFile(at: url, ftp: Double(ftp), weight: weight)
        case .failure(let error):
            print("File import error: \(error)")
        }
    }
    
    func analyzeFile(at url: URL, ftp: Double, weight: Double) {
        isAnalyzing = true
        analysisStatus = "Reading file..."
        
        Task {
            do {
                // Start accessing security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    throw NSError(domain: "FileAccess", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot access file"])
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                analysisStatus = "Parsing FIT data..."
                let dataPoints = try await parser.parseFile(at: url)
                
                analysisStatus = "Analyzing performance..."
                let analysis = analyzer.analyzeRide(
                    dataPoints: dataPoints,
                    ftp: ftp,
                    weight: weight,
                    plannedRide: nil // TODO: Match with saved plans
                )
                
                await MainActor.run {
                    self.currentAnalysis = analysis
                    self.storage.saveAnalysis(analysis)
                    self.loadHistory()
                    self.isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    self.isAnalyzing = false
                    self.analysisStatus = "Error: \(error.localizedDescription)"
                }
                print("Analysis error: \(error)")
            }
        }
    }
    
    func loadHistory() {
        analysisHistory = storage.loadAllAnalyses()
    }
    
    func selectAnalysis(_ analysis: RideAnalysis) {
        currentAnalysis = analysis
    }
    
    func deleteAnalyses(at offsets: IndexSet) {
        for index in offsets {
            storage.deleteAnalysis(analysisHistory[index])
        }
        loadHistory()
    }
    
    func getTrendData() -> [TrendDataPoint] {
        return storage.getAnalysisTrend(limit: 10)
    }
    
    func exportCSV(_ analysis: RideAnalysis) {
        let csv = analysis.exportToCSV()
        let url = saveToTempFile(text: csv, filename: "ride-analysis-\(Date().timeIntervalSince1970).csv")
        shareItem = ShareItem(url: url)
    }
    
    func exportReport(_ analysis: RideAnalysis) {
        let report = analysis.exportToReport()
        let url = saveToTempFile(text: report, filename: "ride-report-\(Date().timeIntervalSince1970).txt")
        shareItem = ShareItem(url: url)
    }
    
    func exportAllHistory() {
        let csv = storage.exportAllToCSV()
        let url = saveToTempFile(text: csv, filename: "all-rides-\(Date().timeIntervalSince1970).csv")
        shareItem = ShareItem(url: url)
    }
    
    private func saveToTempFile(text: String, filename: String) -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? text.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

