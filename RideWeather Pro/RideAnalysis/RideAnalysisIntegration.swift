//
//  UpdatedOptimizedAdvancedCyclingTabView.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 10/19/25.
//


//
//  RideAnalysisIntegration.swift
//  RideWeather Pro
//
//  Integration code to add Ride File Analysis to your existing app
//

import Foundation
import SwiftUI

// MARK: - Add to WeatherViewModel

extension WeatherViewModel {
    
    // Add this property
    @Published var currentRideAnalyzer: RideFileAnalyzer?
    
    // Add this method
    func beginRideAnalysis(fileURL: URL, againstPlan plan: PacingPlan) async {
        let analyzer = RideFileAnalyzer(originalPlan: plan, settings: settings)
        
        // Store it so UI can access
        await MainActor.run {
            self.currentRideAnalyzer = analyzer
        }
        
        // Analyze the file
        await analyzer.analyzeRideFile(fileURL)
    }
}

// MARK: - Add Ride Analysis Tab to Advanced Cycling View

struct UpdatedOptimizedAdvancedCyclingTabView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                OptimizedPacingPlanTab(viewModel: viewModel, selectedTab: $selectedTab)
                    .tag(0)
                    .tabItem {
                        Label("Pacing", systemImage: "speedometer")
                    }
                
                FuelingPlanTab(viewModel: viewModel)
                    .tag(1)
                    .tabItem {
                        Label("Fueling", systemImage: "drop.fill")
                    }
                
                UpdatedOptimizedExportTab(viewModel: viewModel)
                    .tag(2)
                    .tabItem {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                
                // NEW: What-If Scenarios Tab
                whatIfTab
                    .tag(3)
                    .tabItem {
                        Label("What-If", systemImage: "chart.bar.xaxis")
                    }
                
                // NEW: Ride Analysis Tab
                rideAnalysisTab
                    .tag(4)
                    .tabItem {
                        Label("Analysis", systemImage: "doc.text.magnifyingglass")
                    }
            }
            .navigationTitle("Advanced Features")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
    }
    
    // MARK: - What-If Tab
    
    private var whatIfTab: some View {
        Group {
            if let controller = viewModel.advancedController,
               let analysis = viewModel.lastPowerAnalysis {
                WhatIfScenariosView(
                    baseSettings: viewModel.settings,
                    basePowerAnalysis: analysis,
                    baseStartTime: viewModel.rideDate
                )
            } else {
                EmptyStateView(
                    title: "What-If Analysis Unavailable",
                    message: "Generate a pacing plan first to compare scenarios",
                    systemImage: "chart.bar.xaxis"
                )
            }
        }
    }
    
    // MARK: - Ride Analysis Tab
    
    private var rideAnalysisTab: some View {
        Group {
            if let analyzer = viewModel.currentRideAnalyzer {
                // If we already have an analyzer with results, show them
                NavigationStack {
                    Group {
                        if analyzer.isAnalyzing {
                            ProgressView("Analyzing ride file...")
                        } else if let analysis = analyzer.analysis {
                            RideAnalysisResultsView(analysis: analysis, viewModel: viewModel)
                        } else if let error = analyzer.error {
                            ErrorView(error: error) {
                                viewModel.currentRideAnalyzer = nil
                            }
                        } else {
                            EmptyRideAnalysisView(viewModel: viewModel)
                        }
                    }
                }
            } else if let plan = viewModel.advancedController?.pacingPlan {
                // No analyzer yet, show import option
                EmptyRideAnalysisView(viewModel: viewModel)
            } else {
                // No plan yet
                EmptyStateView(
                    title: "Ride Analysis Unavailable",
                    message: "Generate a pacing plan first, then import your ride file to compare",
                    systemImage: "doc.text.magnifyingglass"
                )
            }
        }
    }
}

// MARK: - Empty State for Ride Analysis

struct EmptyRideAnalysisView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @State private var showingFilePicker = false
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            
            VStack(spacing: 8) {
                Text("Analyze Your Ride")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Import your completed ride to see how you performed against your plan")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button(action: { showingFilePicker = true }) {
                Label("Import Ride File", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            
            // Info cards
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(
                    icon: "checkmark.circle.fill",
                    text: "Compare actual vs planned power",
                    color: .green
                )
                InfoRow(
                    icon: "chart.line.uptrend.xyaxis",
                    text: "Identify pacing deviations and surges",
                    color: .blue
                )
                InfoRow(
                    icon: "lightbulb.fill",
                    text: "Get personalized improvement insights",
                    color: .yellow
                )
                InfoRow(
                    icon: "trophy.fill",
                    text: "Track performance score over time",
                    color: .orange
                )
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 40)
        }
        .padding()
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result,
              let fileURL = urls.first,
              let plan = viewModel.advancedController?.pacingPlan else {
            return
        }
        
        Task {
            await viewModel.beginRideAnalysis(fileURL: fileURL, againstPlan: plan)
        }
    }
}

struct InfoRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}

struct ErrorView: View {
    let error: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            
            VStack(spacing: 8) {
                Text("Analysis Failed")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Try Another File") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Results View Wrapper

struct RideAnalysisResultsView: View {
    let analysis: RideAnalysis
    @ObservedObject var viewModel: WeatherViewModel
    @State private var showingExport = false
    @State private var exportType: ExportType = .csv
    
    enum ExportType {
        case csv
        case report
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Performance Score
                PerformanceScoreCard(analysis: analysis)
                
                // Ride Metrics
                RideMetricsCard(analysis: analysis)
                
                // Power Analysis
                if let powerMetrics = analysis.powerMetrics {
                    PowerAnalysisCard(metrics: powerMetrics, settings: viewModel.settings)
                }
                
                // Pacing Analysis
                PacingAnalysisCard(paceAnalysis: analysis.paceAnalysis)
                
                // Segment Comparison
                if !analysis.segmentAnalysis.isEmpty {
                    SegmentComparisonCard(segments: analysis.segmentAnalysis)
                }
                
                // Insights
                if !analysis.insights.isEmpty {
                    InsightsCard(insights: analysis.insights)
                }
                
                // Deviations
                if !analysis.deviations.isEmpty {
                    DeviationsCard(deviations: analysis.deviations)
                }
                
                // Export Options
                VStack(spacing: 12) {
                    Button(action: {
                        exportType = .csv
                        showingExport = true
                    }) {
                        Label("Export as CSV", systemImage: "tablecells")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        exportType = .report
                        showingExport = true
                    }) {
                        Label("Export Detailed Report", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Ride Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Analysis") {
                    viewModel.currentRideAnalyzer = nil
                }
            }
        }
        .sheet(isPresented: $showingExport) {
            ShareSheet(activityItems: [exportContent()])
        }
    }
    
    private func exportContent() -> String {
        switch exportType {
        case .csv:
            return analysis.exportAsCSV()
        case .report:
            return analysis.exportDetailedReport()
        }
    }
}

// MARK: - Quick Actions Menu Addition

extension OptimizedUnifiedRouteAnalyticsDashboard {
    
    // Add this as an additional option in your existing UI
    var rideAnalysisQuickAction: some View {
        Button(action: {
            // Show ride analysis
        }) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analyze Past Ride")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Compare actual performance to plan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Performance History Tracking

@MainActor
final class RideHistoryManager: ObservableObject {
    @Published var rideHistory: [RideAnalysisSummary] = []
    
    private let storageKey = "rideAnalysisHistory"
    
    struct RideAnalysisSummary: Identifiable, Codable {
        let id: UUID
        let date: Date
        let fileName: String
        let performanceScore: Double
        let duration: TimeInterval
        let distance: Double
        let averagePower: Double?
        let normalizedPower: Double?
        let tss: Double?
        
        init(from analysis: RideAnalysis) {
            self.id = UUID()
            self.date = analysis.parsedFile.startTime
            self.fileName = analysis.parsedFile.fileName
            self.performanceScore = analysis.performanceScore
            self.duration = analysis.parsedFile.totalDuration
            self.distance = analysis.parsedFile.totalDistance
            self.averagePower = analysis.powerMetrics?.averagePower
            self.normalizedPower = analysis.powerMetrics?.normalizedPower
            self.tss = analysis.powerMetrics?.tss
        }
    }
    
    init() {
        loadHistory()
    }
    
    func addAnalysis(_ analysis: RideAnalysis) {
        let summary = RideAnalysisSummary(from: analysis)
        rideHistory.insert(summary, at: 0)
        
        // Keep only last 50 rides
        if rideHistory.count > 50 {
            rideHistory = Array(rideHistory.prefix(50))
        }
        
        saveHistory()
    }
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RideAnalysisSummary].self, from: data) else {
            return
        }
        rideHistory = decoded
    }
    
    private func saveHistory() {
        guard let encoded = try? JSONEncoder().encode(rideHistory) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }
    
    func deleteRide(_ id: UUID) {
        rideHistory.removeAll { $0.id == id }
        saveHistory()
    }
    
    func performanceTrend(last count: Int = 10) -> [Double] {
        return Array(rideHistory.prefix(count).map { $0.performanceScore }.reversed())
    }
}

// MARK: - Ride History View

struct RideHistoryView: View {
    @StateObject private var historyManager = RideHistoryManager()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if !historyManager.rideHistory.isEmpty {
                    Section {
                        PerformanceTrendChart(
                            scores: historyManager.performanceTrend(last: 10)
                        )
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets())
                    } header: {
                        Text("Performance Trend (Last 10 Rides)")
                    }
                }
                
                Section {
                    if historyManager.rideHistory.isEmpty {
                        ContentUnavailableView(
                            "No Ride History",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("Analyzed rides will appear here")
                        )
                    } else {
                        ForEach(historyManager.rideHistory) { ride in
                            RideHistoryRow(ride: ride)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                historyManager.deleteRide(historyManager.rideHistory[index].id)
                            }
                        }
                    }
                } header: {
                    Text("Ride History")
                }
            }
            .navigationTitle("Ride History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct RideHistoryRow: View {
    let ride: RideHistoryManager.RideAnalysisSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ride.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                
                Spacer()
                
                Text("\(Int(ride.performanceScore))")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(scoreColor)
            }
            
            Text(ride.fileName)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                Label(
                    formatDuration(ride.duration),
                    systemImage: "clock"
                )
                .font(.caption)
                
                Label(
                    String(format: "%.1f km", ride.distance / 1000),
                    systemImage: "road.lanes"
                )
                .font(.caption)
                
                if let power = ride.normalizedPower {
                    Label(
                        "\(Int(power))W",
                        systemImage: "bolt"
                    )
                    .font(.caption)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var scoreColor: Color {
        switch ride.performanceScore {
        case 85...100: return .green
        case 70..<85: return .blue
        case 50..<70: return .orange
        default: return .red
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct PerformanceTrendChart: View {
    let scores: [Double]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid
                Path { path in
                    for i in 0...4 {
                        let y = geometry.size.height * CGFloat(i) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                
                // Trend line
                if !scores.isEmpty {
                    Path { path in
                        let xStep = geometry.size.width / CGFloat(max(scores.count - 1, 1))
                        
                        for (index, score) in scores.enumerated() {
                            let x = CGFloat(index) * xStep
                            let y = geometry.size.height * (1 - score / 100)
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.blue, lineWidth: 2)
                    
                    // Data points
                    ForEach(Array(scores.enumerated()), id: \.offset) { index, score in
                        let xStep = geometry.size.width / CGFloat(max(scores.count - 1, 1))
                        let x = CGFloat(index) * xStep
                        let y = geometry.size.height * (1 - score / 100)
                        
                        Circle()
                            .fill(scoreColor(score))
                            .frame(width: 8, height: 8)
                            .position(x: x, y: y)
                    }
                }
            }
        }
        .padding()
    }
    
    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 85...100: return .green
        case 70..<85: return .blue
        case 50..<70: return .orange
        default: return .red
        }
    }
}

// MARK: - Add History Button to Main View

extension OptimizedAdvancedCyclingTabView {
    
    // Add this to your toolbar
    var historyButton: some View {
        Button(action: {
            // Show history
        }) {
            Image(systemName: "clock.arrow.circlepath")
        }
    }
}

// MARK: - Comparison Between Multiple Rides

struct MultiRideComparisonView: View {
    let rides: [RideHistoryManager.RideAnalysisSummary]
    @State private var selectedMetric: Metric = .performanceScore
    
    enum Metric: String, CaseIterable {
        case performanceScore = "Performance Score"
        case averagePower = "Average Power"
        case normalizedPower = "Normalized Power"
        case tss = "TSS"
        
        func value(from ride: RideHistoryManager.RideAnalysisSummary) -> Double? {
            switch self {
            case .performanceScore: return ride.performanceScore
            case .averagePower: return ride.averagePower
            case .normalizedPower: return ride.normalizedPower
            case .tss: return ride.tss
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Picker("Metric", selection: $selectedMetric) {
                ForEach(Metric.allCases, id: \.self) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(rides) { ride in
                        if let value = selectedMetric.value(from: ride) {
                            ComparisonBar(
                                ride: ride,
                                value: value,
                                maxValue: maxValue(for: selectedMetric)
                            )
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Compare Rides")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func maxValue(for metric: Metric) -> Double {
        rides.compactMap { metric.value(from: $0) }.max() ?? 100
    }
}

struct ComparisonBar: View {
    let ride: RideHistoryManager.RideAnalysisSummary
    let value: Double
    let maxValue: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ride.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(String(format: "%.0f", value))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.quaternary)
                    
                    Rectangle()
                        .fill(.blue.gradient)
                        .frame(width: geometry.size.width * (value / maxValue))
                }
            }
            .frame(height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Auto-Save Analysis Results

extension RideFileAnalyzer {
    
    func saveAnalysisIfSuccessful() {
        guard let analysis = analysis else { return }
        
        // Save to history
        let historyManager = RideHistoryManager()
        historyManager.addAnalysis(analysis)
        
        print("✅ Ride analysis saved to history")
    }
}

// MARK: - Usage Instructions

/*
 
 INTEGRATION STEPS:
 
 1. Add to WeatherViewModel:
    @Published var currentRideAnalyzer: RideFileAnalyzer?
    @Published var lastPowerAnalysis: PowerRouteAnalysisResult?
 
 2. Update your existing generateAdvancedCyclingPlan to store the analysis:
    self.lastPowerAnalysis = powerAnalysis
 
 3. Replace OptimizedAdvancedCyclingTabView with UpdatedOptimizedAdvancedCyclingTabView
 
 4. Add RideHistoryManager as a StateObject in your main view
 
 5. Optional: Add a history button to your main analytics dashboard:
    - Shows performance trends
    - Allows comparing multiple rides
    - Quick access to past analyses
 
 FEATURES INCLUDED:
 
 ✅ FIT file parsing (native Swift implementation)
 ✅ GPX file support (extensible)
 ✅ Comprehensive performance analysis
 ✅ Power metrics (NP, TSS, VI, peak powers)
 ✅ Pacing consistency scoring
 ✅ Segment-by-segment comparison
 ✅ Fatigue detection
 ✅ Personalized insights & recommendations
 ✅ Deviation tracking (surges, etc.)
 ✅ Performance scoring (0-100)
 ✅ CSV & detailed report export
 ✅ Ride history tracking
 ✅ Performance trend visualization
 ✅ Multi-ride comparison
 
 EXAMPLE USAGE:
 
 // After completing a ride
 if let plan = viewModel.advancedController?.pacingPlan {
     let fileURL = URL(fileURLWithPath: "path/to/ride.fit")
     await viewModel.beginRideAnalysis(fileURL: fileURL, againstPlan: plan)
 }
 
 // View results in the Analysis tab
 
 */