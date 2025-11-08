//
// RideAnalysisView.swift
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

// MARK: - Main Analysis View

struct RideAnalysisView: View {
    @StateObject private var viewModel: RideAnalysisViewModel  // Change this
    @ObservedObject var weatherViewModel: WeatherViewModel
    @EnvironmentObject var stravaService: StravaService
    @EnvironmentObject var wahooService: WahooService // Add this
    
    private let trainingLoadManager = TrainingLoadManager.shared

    // 🔥 ADD CUSTOM INIT
    init(weatherViewModel: WeatherViewModel) {
        self.weatherViewModel = weatherViewModel
        // Create the viewModel with settings
        self._viewModel = StateObject(wrappedValue: RideAnalysisViewModel(settings: weatherViewModel.settings))
    }

    var body: some View {
        NavigationView {
            Group {
                if viewModel.currentAnalysis == nil {
                    emptyStateView
                } else {
                    analysisResultsView
                }
            }
//            .navigationTitle("Ride Analysis")
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
                        if wahooService.isAuthenticated {
                            Button(action: { viewModel.showingWahooActivities = true }) {
                                Label("Import from Wahoo", systemImage: "square.and.arrow.down.on.square")
                            }
                        }
                        // ✅ ADD THIS
                        Divider()
                        Button(action: { viewModel.showingSavedPlans = true }) {
                            Label("Saved Pacing Plans", systemImage: "list.bullet.rectangle")
                        }

                        // ✅ ADD THIS
                        if viewModel.currentAnalysis != nil {
                            Divider()
                            Button(action: {
                                if let analysis = viewModel.currentAnalysis {
                                    viewModel.compareToPlans(analysis)
                                }
                            }) {
                                Label("Compare to Plan", systemImage: "chart.bar.xaxis")
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
            .animatedBackground(
                 gradient: .rideAnalysisBackground,
                 showDecoration: true,
                 decorationColor: .white,
                 decorationIntensity: 0.06
             )
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
            .sheet(isPresented: $viewModel.showingStravaActivities) {
                StravaActivitiesView()
                    .environmentObject(stravaService)
                    .environmentObject(weatherViewModel)
            }
            .sheet(isPresented: $viewModel.showingWahooActivities) {
                WahooActivitiesView()
                    .environmentObject(wahooService)
                    .environmentObject(weatherViewModel)
            }
            .sheet(isPresented: $viewModel.showingPlanComparison) {
                if let analysis = viewModel.currentAnalysis {
                    ComparisonSelectionView(analysis: analysis)
                }
            }
            .sheet(isPresented: $viewModel.showingSavedPlans) {
                SavedPlansView()
            }
            // ✅ ADD THIS - Listen for Strava imports
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewAnalysisImported"))) { notification in
                if let analysis = notification.object as? RideAnalysis {
                    viewModel.currentAnalysis = analysis
                    if let source = notification.userInfo?["source"] as? String, source == "strava" {
                        let sourceInfo = RideSourceInfo(
                            type: .strava,
                            fileName: nil
                        )
                        viewModel.analysisSources[analysis.id] = sourceInfo
                        viewModel.storage.saveSource(sourceInfo, for: analysis.id)
                    }
                    viewModel.loadHistory()
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
            
            if wahooService.isAuthenticated {
                Button(action: { viewModel.showingWahooActivities = true }) {
                    HStack(spacing: 12) {
                        Image("wahoo_logo") // Wahoo icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                        Text("Import from Wahoo")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.8)) // Wahoo blue
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
//                        RideMetadataCard(analysis: analysis, useMetric: weatherViewModel.settings.units == .metric)
                        // ✅ NEW: Compact header replaces RideMetadataCard
                        CompactRideHeaderCard(
                            analysis: analysis,
                            source: viewModel.getRideSource(for: analysis)
                        )
                             .id("top")

                        // Add the map card right here
                        if let breadcrumbs = analysis.metadata?.routeBreadcrumbs, !breadcrumbs.isEmpty {
                            RideRouteMapCard(
                                routeBreadcrumbs: breadcrumbs,
                                analysisID: analysis.id // <-- PASS THE ID HERE
                            )
                            .aspectRatio(1.6, contentMode: .fit) // Give it a nice landscape ratio
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                        }
                        
                        // Add Heart Rate Graph
                        if let hrData = analysis.heartRateGraphData, let avgHR = analysis.averageHeartRate, !hrData.isEmpty {
                            HeartRateGraphCard(hrData: hrData,
                                               avgHR: avgHR,
                                               elevationData: analysis.elevationGraphData)
                        }
                        
                        // Add Power Graph
                        if let powerData = analysis.powerGraphData, !powerData.isEmpty {
                            PowerGraphCard(powerData: powerData,
                                           avgPower: analysis.averagePower,
                                           elevationData: analysis.elevationGraphData)
                        }
                        
                        // Performance Score Card
                        PerformanceScoreCard(analysis: analysis)
                        
                        // Training Load
                        TrainingLoadContext(analysis: analysis)

                        // Comparison prompt (optional)
                        if let analysis = viewModel.currentAnalysis {
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "chart.bar.xaxis")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Compare to Pacing Plan")
                                            .font(.headline)
                                        Text("See where you could improve time")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                                
                                Button(action: { viewModel.compareToPlans(analysis) }) {
                                    Text("Compare Now")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.blue)
                                        .cornerRadius(12)
                                }
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                        }
                        
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

// MARK: - 🔥 NEW Compact Ride Header (replaces RideMetadataCard)

struct CompactRideHeaderCard: View {
    let analysis: RideAnalysis
    let source: RideSource
    
    enum RideSource {
        case strava
        case wahoo
        case fitFile(fileName: String)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ride Analysis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(analysis.rideName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                }
                
                Spacer()
            }
            
            HStack {
                Image(systemName: sourceIcon)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                
                Text("Source: \(sourceText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Date row
            if let metadata = analysis.metadata {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    
                    Text(metadata.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var sourceIcon: String {
        switch source {
        case .strava:
            return "figure.outdoor.cycle"
        case .wahoo:
            return "figure.outdoor.cycle"
        case .fitFile:
            return "doc.fill"
        }
    }
    
    private var sourceText: String {
        switch source {
        case .strava:
            return "Strava"  // ✅ Shows "Strava"
        case .wahoo:
            return "Wahoo"  // ✅ Shows "Wahoo"
        case .fitFile(let fileName):
            return fileName  // ✅ Shows full filename with .fit extension
        }
    }
}

// MARK: - Terrain Segments Card

struct TerrainSegmentsCard: View {
    let analysis: RideAnalysis
    
    private var actionableSegments: [ActionableSegmentInsight] {
        guard let segments = analysis.terrainSegments else { return [] }
        
        var insights: [ActionableSegmentInsight] = []
        
        // Group segments by type and find the most impactful opportunities
        let climbs = segments.filter { $0.type == .climb }
        let flats = segments.filter { $0.type == .flat || $0.type == .rolling }
        
        // Find significant climbs where power was too low
        let underPoweredClimbs = climbs.filter {
            $0.duration > 60 && // At least 1 minute
            $0.powerEfficiency < 85 && // Less than 85% of optimal
            $0.distance > 200 // At least 200m
        }.sorted {
            // Sort by potential time savings
            ($0.optimalPowerForTime - $0.averagePower) * $0.duration >
            ($1.optimalPowerForTime - $1.averagePower) * $1.duration
        }
        
        // Add climb insights (top 3)
        for climb in underPoweredClimbs.prefix(3) {
            let timeLost = estimateTimeLost(
                actualPower: climb.averagePower,
                optimalPower: climb.optimalPowerForTime,
                distance: climb.distance,
                grade: climb.gradient
            )
            
            if timeLost > 3 { // Only show if >3 seconds lost
                insights.append(ActionableSegmentInsight(
                    title: "Climb at \(formatDistance(climb.distance))",
                    terrainType: climb.type,
                    issue: "Left time on the table",
                    details: """
                    Grade: \(String(format: "%.1f%%", climb.gradient * 100))
                    Duration: \(formatDuration(climb.duration))
                    You averaged: \(Int(climb.averagePower))W
                    Optimal would be: \(Int(climb.optimalPowerForTime))W
                    """,
                    impact: "~\(Int(timeLost))s slower than optimal",
                    recommendation: "On climbs this steep, push \(Int(climb.optimalPowerForTime - climb.averagePower))W harder. Watts translate almost linearly to speed uphill.",
                    priority: timeLost > 15 ? .high : .medium
                ))
            }
        }
        
        // Find flats where power was too variable or too high
        let inefficientFlats = flats.filter {
            $0.duration > 120 && // At least 2 minutes
            ($0.powerEfficiency > 110 || $0.powerEfficiency < 70)
        }
        
        for flat in inefficientFlats.prefix(2) {
            if flat.powerEfficiency > 110 {
                insights.append(ActionableSegmentInsight(
                    title: "Flat section at \(formatDistance(flat.distance))",
                    terrainType: flat.type,
                    issue: "Wasted energy",
                    details: """
                    Duration: \(formatDuration(flat.duration))
                    You averaged: \(Int(flat.averagePower))W
                    More efficient: \(Int(flat.optimalPowerForTime))W
                    """,
                    impact: "Energy wasted that could be saved for climbs",
                    recommendation: "On flats, aero matters more than power. Focus on position and steady effort around \(Int(flat.optimalPowerForTime))W.",
                    priority: .medium
                ))
            }
        }
        
        return insights
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Where You Can Improve")
                .font(.headline)
            
            if actionableSegments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.green)
                    Text("Well-executed ride!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Your power distribution was efficient for the terrain")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                VStack(spacing: 12) {
                    ForEach(actionableSegments) { insight in
                        ActionableSegmentInsightRow(insight: insight)
                    }
                }
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1fkm", meters / 1000)
        }
        return "\(Int(meters))m"
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if minutes > 0 {
            return "\(minutes):\(String(format: "%02d", secs))"
        }
        return "\(secs)s"
    }
    
    private func estimateTimeLost(actualPower: Double, optimalPower: Double, distance: Double, grade: Double) -> TimeInterval {
        guard actualPower > 0 && optimalPower > 0 else { return 0 }
        
        // On climbs, power is roughly linear with speed
        let powerRatio = optimalPower / actualPower
        let speedImprovement = pow(powerRatio, 0.33) // Physics approximation
        
        let estimatedSpeed = actualPower / 10.0 // Very rough m/s estimate
        let actualTime = distance / estimatedSpeed
        let optimalTime = distance / (estimatedSpeed * speedImprovement)
        
        return max(0, actualTime - optimalTime)
    }
}

struct ActionableSegmentInsight: Identifiable {
    let id = UUID()
    let title: String
    let terrainType: TerrainSegment.TerrainType
    let issue: String
    let details: String
    let impact: String
    let recommendation: String
    let priority: Priority
    
    enum Priority {
        case high, medium, low
        
        var color: Color {
            switch self {
            case .high: return .red
            case .medium: return .orange
            case .low: return .blue
            }
        }
        
        var icon: String {
            switch self {
            case .high: return "exclamationmark.triangle.fill"
            case .medium: return "info.circle.fill"
            case .low: return "lightbulb.fill"
            }
        }
    }
}

struct ActionableSegmentInsightRow: View {
    let insight: ActionableSegmentInsight
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: insight.terrainType.emoji)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(insight.issue)
                        .font(.caption)
                        .foregroundColor(insight.priority.color)
                }
                
                Spacer()
                
                Image(systemName: insight.priority.icon)
                    .foregroundColor(insight.priority.color)
                    .font(.title3)
            }
            
            // Impact
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(insight.impact)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    // Details
                    Text(insight.details)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                    
                    // Recommendation
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                        
                        Text(insight.recommendation)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text(isExpanded ? "Show Less" : "How to Improve")
                        .font(.caption)
                        .fontWeight(.medium)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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

// MARK: - Power Allocation Card - REDESIGNED for Clarity

struct PowerAllocationCard: View {
    let analysis: RideAnalysis
    
    private var timeSavingsMessage: String {
        guard let allocation = analysis.powerAllocation else { return "" }
        
        let seconds = allocation.estimatedTimeSaved
        if seconds < 5 {
            return "You distributed power efficiently for the terrain"
        } else if seconds < 30 {
            return "Small adjustments could save ~\(Int(seconds))s"
        } else if seconds < 60 {
            return "Better power distribution could save ~\(Int(seconds))s"
        } else {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "You could have finished \(minutes):\(String(format: "%02d", secs)) faster"
        }
    }
    
    private var mainIssue: String? {
        guard let allocation = analysis.powerAllocation else { return nil }
        
        // Calculate where power was allocated
        let climbPercent = (allocation.wattsUsedOnClimbs / allocation.totalWatts) * 100
        let flatPercent = (allocation.wattsUsedOnFlats / allocation.totalWatts) * 100
        
        // Typical optimal split is 60-70% climbing, 30-40% flats for hilly routes
        if climbPercent < 50 && allocation.estimatedTimeSaved > 10 {
            return "You held back too much on climbs. That's where watts = speed."
        } else if flatPercent > 50 && allocation.estimatedTimeSaved > 10 {
            return "You used too much energy on flats. Save it for the climbs."
        }
        
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Power Strategy Analysis")
                .font(.headline)
            
            if let allocation = analysis.powerAllocation {
                VStack(spacing: 16) {
                    // Main message - what does this mean?
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: allocation.estimatedTimeSaved > 10 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundColor(allocation.estimatedTimeSaved > 10 ? .orange : .green)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(timeSavingsMessage)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                
                                if let issue = mainIssue {
                                    Text(issue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Visual breakdown of where power went
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Where Your Energy Went")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        PowerBreakdownBar(
                            climbWatts: allocation.wattsUsedOnClimbs,
                            flatWatts: allocation.wattsUsedOnFlats,
                            descentWatts: allocation.wattsUsedOnDescents,
                            totalWatts: allocation.totalWatts
                        )
                        
                        // Explanation of what this means
                        if allocation.estimatedTimeSaved > 10 {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.caption)
                                        .foregroundColor(.yellow)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Why This Matters")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                        
                                        Text("On climbs, every extra watt directly makes you faster. On flats, aero position matters more than raw power. Push harder uphill, recover on flats.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color.yellow.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    // Show specific recommendations if available
                    if !allocation.recommendations.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Specific Opportunities")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            ForEach(allocation.recommendations.prefix(3), id: \.segment.id) { rec in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(rec.segment.type.emoji)
                                        .font(.title3)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(Int(rec.segment.distance))m \(rec.segment.type.rawValue)")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        
                                        Text("Push \(Int(rec.optimalPower - rec.actualPower))W harder → save ~\(Int(rec.timeLost))s")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
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
    
    private var pacingInterpretation: (rating: String, color: Color, advice: String) {
        let score = analysis.consistencyScore
        
        switch score {
        case 90...100:
            return ("Excellent", .green, "You maintained steady power throughout. This is textbook pacing.")
        case 80..<90:
            return ("Very Good", .blue, "Solid pacing with minor fluctuations. A few surges but overall controlled.")
        case 70..<80:
            return ("Good", .cyan, "Decent pacing with room for improvement. Work on smoothing out power spikes.")
        case 60..<70:
            return ("Fair", .yellow, "Inconsistent pacing detected. Focus on maintaining steadier effort.")
        case 50..<60:
            return ("Needs Work", .orange, "Significant power variability. This costs energy without speed gains.")
        default:
            return ("Poor", .red, "Very erratic pacing. Practice riding at consistent power targets.")
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pacing Execution")
                .font(.headline)
            
            HStack(spacing: 20) {
                // Consistency Gauge
                VStack {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                        
                        Circle()
                            .trim(from: 0, to: analysis.consistencyScore / 100)
                            .stroke(pacingInterpretation.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        
                        VStack(spacing: 2) {
                            Text("\(Int(analysis.consistencyScore))")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("/ 100")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 80, height: 80)
                    
                    Text(pacingInterpretation.rating)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(pacingInterpretation.color)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(pacingInterpretation.advice)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if analysis.surgeCount > 5 {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("\(analysis.surgeCount) power surges detected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if analysis.fatigueDetected, let onset = analysis.fatigueOnsetTime {
                Divider()
                
                fatigueCard(onsetTime: onset, totalTime: analysis.duration)
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private func fatigueCard(onsetTime: TimeInterval, totalTime: TimeInterval) -> some View {
        let onsetMinutes = Int(onsetTime / 60)
        let totalMinutes = Int(totalTime / 60)
        let onsetPercentage = (onsetTime / totalTime) * 100
        
        let (icon, color, message, advice): (String, Color, String, String) = {
            if onsetPercentage < 30 {
                return ("exclamationmark.triangle.fill", .red,
                       "Fatigue hit early at \(onsetMinutes) minutes",
                       "You started too hard. The first 20% should feel uncomfortably easy - save your matches for later.")
            } else if onsetPercentage < 60 {
                return ("info.circle.fill", .orange,
                       "Power declined after \(onsetMinutes) minutes",
                       "Mid-ride fade suggests pacing or nutrition issues. Fuel every 20-30 minutes and pace more conservatively early.")
            } else {
                return ("checkmark.circle.fill", .yellow,
                       "Fatigue in final \(totalMinutes - onsetMinutes) minutes",
                       "Normal fade for a \(totalMinutes)-minute effort. This is expected - you paced well.")
            }
        }()
        
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                
                Text(advice)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(color.opacity(0.1))
        .cornerRadius(8)
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
/*                        Section {
                            TrendChartView(trendData: viewModel.getTrendData())
                                .frame(height: 200)
                                .listRowInsets(EdgeInsets())
                        }*/
                        
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

// Create new view for RideAnalysisView.swift:

struct TrainingLoadContext: View {
    let analysis: RideAnalysis
    @State private var summary: TrainingLoadSummary?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training Load Impact")
                .font(.headline)
            
            if let summary = summary {
                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("TSS")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(Int(analysis.trainingStressScore))")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading) {
                        Text("7-Day Total")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(Int(summary.weeklyTSS))")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading) {
                        Text("Form")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(summary.formStatus.emoji)
                            .font(.title3)
                    }
                }
                
                Text(summary.formStatus.rawValue)
                    .font(.caption)
                    .foregroundColor(Color(summary.formStatus.color))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .onAppear {
            summary = TrainingLoadManager.shared.getCurrentSummary()
        }
    }
}

// MARK: - Ride Source Info

struct RideSourceInfo: Codable {
    let type: SourceType
    let fileName: String?
    
    enum SourceType: String, Codable {
        case strava
        case wahoo
        case fitFile
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
    @Published var showingWahooActivities = false 
    @Published var showingSavedPlans = false
    
    @Published var showingPlanComparison = false
    @Published var showingComparisonSelection = false
    // ✅ NEW: Track source information
    @Published var analysisSources: [UUID: RideSourceInfo] = [:]

    private let parser = FITFileParser()
    let storage = AnalysisStorageManager()
    private let settings: AppSettings  // 🔥 ADD THIS

    @MainActor  // Add this
    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    @MainActor
    func loadInitialData() {
        // This is safe to call from onAppear
        if analysisHistory.isEmpty { // Only load if we haven't
            loadHistory()
            self.analysisSources = storage.loadAllSources()
        }
    }
    
    // ✅ NEW: Get ride source for display
    func getRideSource(for analysis: RideAnalysis) -> CompactRideHeaderCard.RideSource {
        if let sourceInfo = analysisSources[analysis.id] {
            switch sourceInfo.type {
            case .strava:
                return .strava
            case .wahoo:
                return .wahoo
            case .fitFile:
                return .fitFile(fileName: sourceInfo.fileName ?? "Unknown File")
            }
        }
        return .fitFile(fileName: "Imported Ride")
    }
 
    func handleFileImport(result: Result<[URL], Error>, ftp: Int, weight: Double) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let fileName = url.deletingPathExtension().lastPathComponent
            analyzeFile(at: url, ftp: Double(ftp), weight: weight, fileName: fileName)
        case .failure(let error):
            print("File import error: \(error)")
        }
    }
    
    func analyzeFile(at url: URL, ftp: Double, weight: Double, fileName: String? = nil) {
        isAnalyzing = true
        analysisStatus = "Reading file..."
        
        Task {
            do {
                guard url.startAccessingSecurityScopedResource() else {
                    throw NSError(domain: "FileAccess", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot access file"])
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                // ✅ Extract both the name without extension and the full filename
                let fileNameWithoutExtension = fileName ?? url.deletingPathExtension().lastPathComponent
                let fullFileName = url.lastPathComponent  // ✅ ADD THIS - includes .fit extension

                analysisStatus = "Parsing FIT data..."
                let dataPoints = try await parser.parseFile(at: url)
                
                analysisStatus = "Analyzing performance..."
                let analyzer = RideFileAnalyzer(settings: self.settings)

                // 1. Generate graph data and avg HR *first*
                let (powerGraphData, hrGraphData, elevationGraphData) = analyzer.generateGraphData(dataPoints: dataPoints)
                let heartRates = dataPoints.compactMap { $0.heartRate }
                let averageHeartRate = heartRates.isEmpty ? nil : (Double(heartRates.reduce(0, +)) / Double(heartRates.count))
                
                // 2. Call the original analyzeRide function
                var analysis = analyzer.analyzeRide(
                    dataPoints: dataPoints,
                    ftp: ftp,
                    weight: weight,
                    plannedRide: nil,
                    // Pass the newly generated data to the analyzer
                    averageHeartRate: averageHeartRate,
                    powerGraphData: powerGraphData,
                    heartRateGraphData: hrGraphData,
                    elevationGraphData: elevationGraphData
                )
                
                // 3. Update the ride name
                analysis.rideName = fileNameWithoutExtension
                
                // ✅ NEW: Update the ride name to use the filename
                analysis = RideAnalysis(
                    id: analysis.id,
                    date: analysis.date,
                    rideName: fileNameWithoutExtension,  // ✅ Use filename as ride name
                    duration: analysis.duration,
                    distance: analysis.distance,
                    metadata: analysis.metadata,
                    averagePower: analysis.averagePower,
                    normalizedPower: analysis.normalizedPower,
                    intensityFactor: analysis.intensityFactor,
                    trainingStressScore: analysis.trainingStressScore,
                    variabilityIndex: analysis.variabilityIndex,
                    peakPower5s: analysis.peakPower5s,
                    peakPower1min: analysis.peakPower1min,
                    peakPower5min: analysis.peakPower5min,
                    peakPower20min: analysis.peakPower20min,
                    terrainSegments: analysis.terrainSegments,
                    powerAllocation: analysis.powerAllocation,
                    consistencyScore: analysis.consistencyScore,
                    pacingRating: analysis.pacingRating,
                    powerVariability: analysis.powerVariability,
                    fatigueDetected: analysis.fatigueDetected,
                    fatigueOnsetTime: analysis.fatigueOnsetTime,
                    powerDeclineRate: analysis.powerDeclineRate,
                    plannedRideId: analysis.plannedRideId,
                    segmentComparisons: analysis.segmentComparisons,
                    overallDeviation: analysis.overallDeviation,
                    surgeCount: analysis.surgeCount,
                    pacingErrors: analysis.pacingErrors,
                    performanceScore: analysis.performanceScore,
                    insights: analysis.insights,
                    powerZoneDistribution: analysis.powerZoneDistribution,
                    averageHeartRate: analysis.averageHeartRate,
                    powerGraphData: analysis.powerGraphData,
                    heartRateGraphData: analysis.heartRateGraphData,
                    elevationGraphData: analysis.elevationGraphData
                )
                
                await MainActor.run {
                    self.currentAnalysis = analysis
                    // ✅ CHANGED: Store full filename with extension for source
                    self.analysisSources[analysis.id] = RideSourceInfo(
                        type: .fitFile,
                        fileName: fullFileName  // Use full filename with .fit extension
                    )
                    self.storage.saveSource(analysisSources[analysis.id]!, for: analysis.id)
                    self.storage.saveAnalysis(analysis)
                    TrainingLoadManager.shared.addRide(analysis: analysis)
                    
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
    
    func compareToPlans(_ analysis: RideAnalysis) {
        showingPlanComparison = true
    }

    func loadHistory() {
        analysisHistory = storage.loadAllAnalyses()
        analysisSources = storage.loadAllSources()
    }
    
    func selectAnalysis(_ analysis: RideAnalysis) {
        currentAnalysis = analysis
        
        if analysisSources[analysis.id] == nil {
            if analysis.rideName.contains("Morning Ride") ||
               analysis.rideName.contains("Afternoon Ride") ||
               analysis.rideName.contains("Evening Ride") {
                analysisSources[analysis.id] = RideSourceInfo(
                    type: .strava,
                    fileName: nil
                )
            } else {
                analysisSources[analysis.id] = RideSourceInfo(
                    type: .fitFile,
                    fileName: "Imported Ride"
                )
            }
        }
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

// Better approach: Store source info with analysis
extension AnalysisStorageManager {
    private var sourceStorageKey: String { "analysisSourceInfo" }
    
    // ✅ This doesn't need @MainActor
    func saveSource(_ source: RideSourceInfo, for analysisId: UUID) {
        var sources = loadAllSources()
        sources[analysisId] = source
        
        if let encoded = try? JSONEncoder().encode(sources) {
            UserDefaults.standard.set(encoded, forKey: sourceStorageKey)
        }
    }
    
    // ✅ This doesn't need @MainActor either
    func loadAllSources() -> [UUID: RideSourceInfo] {
        guard let data = UserDefaults.standard.data(forKey: sourceStorageKey),
              let sources = try? JSONDecoder().decode([UUID: RideSourceInfo].self, from: data) else {
            return [:]
        }
        return sources
    }
}
