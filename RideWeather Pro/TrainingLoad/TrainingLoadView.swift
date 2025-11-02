//
//  TrainingLoadView.swift
//  RideWeather Pro
//
//  Main training load tracking interface
//

import SwiftUI
import Charts
import Combine

struct TrainingLoadView: View {
    @StateObject private var viewModel = TrainingLoadViewModel()
    @StateObject private var syncManager = TrainingLoadSyncManager()
    @EnvironmentObject private var stravaService: StravaService
    @EnvironmentObject private var weatherViewModel: WeatherViewModel
    @State private var selectedPeriod: TrainingLoadPeriod = .month
    @State private var showingExplanation = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let summary = viewModel.summary {
                        // Sync Status Banner (if applicable)
                        if stravaService.isAuthenticated {
                            SyncStatusBanner(
                                syncManager: syncManager,
                                onSync: {
                                    Task {
                                        await syncManager.syncFromStrava(
                                            stravaService: stravaService,
                                            userFTP: Double(weatherViewModel.settings.functionalThresholdPower),
                                            userLTHR: nil
                                        )
                                        viewModel.refresh()
                                    }
                                }
                            )
                        }
                        
                        // Current Status Card
                        CurrentFormCard(summary: summary)
                        
                        // Training Load Chart
                        TrainingLoadChart(
                            dailyLoads: viewModel.dailyLoads,
                            period: selectedPeriod
                        )
                        
                        // Period Selector
                        periodSelector
                        
                        // Key Metrics
                        MetricsGrid(summary: summary)
                        
                        // Insights
                        TrainingLoadInsightsSection(insights: viewModel.insights)
                        
                    } else {
                        emptyStateView
                    }
                }
                .padding()
            }
            .navigationTitle("Training Load")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if stravaService.isAuthenticated && !syncManager.isSyncing {
                        Button {
                            Task {
                                await syncManager.syncFromStrava(
                                    stravaService: stravaService,
                                    userFTP: Double(weatherViewModel.settings.functionalThresholdPower),
                                    userLTHR: nil
                                )
                                viewModel.refresh()
                            }
                        } label: {
                            Label("Sync", systemImage: syncManager.needsSync ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                                .foregroundColor(syncManager.needsSync ? .orange : .blue)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingExplanation = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .overlay {
                if syncManager.isSyncing {
                    syncingOverlay
                }
            }
            .sheet(isPresented: $showingExplanation) {
                TrainingLoadExplanationView()
            }
            .onAppear {
                syncManager.loadSyncDate()
                viewModel.refresh()
            }
        }
    }
    
    private var syncingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView(value: syncManager.syncProgress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .frame(width: 200)
                
                Text(syncManager.syncStatus)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
            )
        }
    }
    
    private var periodSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(TrainingLoadPeriod.allPeriods, id: \.days) { period in
                    Button {
                        selectedPeriod = period
                        viewModel.loadPeriod(period)
                    } label: {
                        Text(period.name)
                            .font(.subheadline)
                            .fontWeight(selectedPeriod.days == period.days ? .semibold : .regular)
                            .foregroundColor(selectedPeriod.days == period.days ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedPeriod.days == period.days ? Color.blue : Color(.systemGray6))
                            )
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 70))
                .foregroundColor(.secondary)
            
            Text("No Training Data Yet")
                .font(.title2)
                .fontWeight(.bold)
            
            if stravaService.isAuthenticated {
                Text("Sync your activities from Strava to start tracking your fitness, fatigue, and form over time.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Button {
                    Task {
                        await syncManager.syncFromStrava(
                            stravaService: stravaService,
                            userFTP: Double(weatherViewModel.settings.functionalThresholdPower),
                            userLTHR: nil
                        )
                        viewModel.refresh()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync from Strava")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .disabled(syncManager.isSyncing)
                
                if let lastSync = syncManager.lastSyncDate {
                    Text("Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Connect to Strava in Settings to automatically track your training load from all activities.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Text("Connect in Settings → Strava")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .padding(.top, 8)
            }
            
            Button {
                showingExplanation = true
            } label: {
                Label("Learn About Training Load", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            .padding(.top)
            
            Spacer()
        }
    }
}

// MARK: - Current Form Card

struct CurrentFormCard: View {
    let summary: TrainingLoadSummary
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Current Form")
                    .font(.headline)
                
                Spacer()
                
                Text(summary.formStatus.emoji)
                    .font(.title)
            }
            
            HStack(spacing: 0) {
                FormIndicator(
                    value: summary.currentTSB,
                    status: summary.formStatus
                )
            }
            
            Text(summary.formStatus.rawValue)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(Color(summary.formStatus.color))
            
            Text(summary.recommendation)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct FormIndicator: View {
    let value: Double
    let status: DailyTrainingLoad.FormStatus
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background bar
                Rectangle()
                    .fill(Color(.systemGray6))
                    .frame(height: 30)
                    .cornerRadius(15)
                
                // Indicator
                let normalizedPosition = normalizePosition(value, in: geometry.size.width)
                Circle()
                    .fill(Color(status.color))
                    .frame(width: 40, height: 40)
                    .shadow(radius: 4)
                    .offset(x: normalizedPosition - 20)
                
                // Center line
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 2, height: 40)
                    .offset(x: geometry.size.width / 2 - 1)
            }
        }
        .frame(height: 40)
    }
    
    private func normalizePosition(_ value: Double, in width: CGFloat) -> CGFloat {
        // Map TSB (-40 to +20) to width (0 to width)
        let minTSB: Double = -40
        let maxTSB: Double = 20
        let clamped = max(minTSB, min(maxTSB, value))
        let normalized = (clamped - minTSB) / (maxTSB - minTSB)
        return CGFloat(normalized) * width
    }
}

// MARK: - Training Load Chart

struct TrainingLoadChart: View {
    let dailyLoads: [DailyTrainingLoad]
    let period: TrainingLoadPeriod
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training Load Trend")
                .font(.headline)
            
            if dailyLoads.isEmpty {
                Text("No data for this period")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    // CTL (Fitness) - Blue line
                    ForEach(dailyLoads) { load in
                        if let ctl = load.ctl {
                            LineMark(
                                x: .value("Date", load.date),
                                y: .value("CTL", ctl)
                            )
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                    
                    // ATL (Fatigue) - Orange line
                    ForEach(dailyLoads) { load in
                        if let atl = load.atl {
                            LineMark(
                                x: .value("Date", load.date),
                                y: .value("ATL", atl)
                            )
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                    
                    // TSB (Form) - Area
                    ForEach(dailyLoads) { load in
                        if let tsb = load.tsb {
                            AreaMark(
                                x: .value("Date", load.date),
                                y: .value("TSB", tsb)
                            )
                            .foregroundStyle(.green.opacity(0.2))
                        }
                    }
                }
                .frame(height: 250)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: period.days < 30 ? 7 : 30)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                
                // Legend
                HStack(spacing: 20) {
                    TrainingLoadLegendItem(color: .blue, label: "Fitness (CTL)")
                    TrainingLoadLegendItem(color: .orange, label: "Fatigue (ATL)")
                    TrainingLoadLegendItem(color: .green, label: "Form (TSB)")
                }
                .font(.caption)
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct TrainingLoadLegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Metrics Grid

struct MetricsGrid: View {
    let summary: TrainingLoadSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key Metrics")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                MetricCard(
                    title: "Fitness (CTL)",
                    value: String(format: "%.1f", summary.currentCTL),
                    subtitle: "Long-term load",
                    color: .blue
                )
                
                MetricCard(
                    title: "Fatigue (ATL)",
                    value: String(format: "%.1f", summary.currentATL),
                    subtitle: "Recent load",
                    color: .orange
                )
                
                MetricCard(
                    title: "Form (TSB)",
                    value: String(format: "%.1f", summary.currentTSB),
                    subtitle: summary.formStatus.rawValue,
                    color: Color(summary.formStatus.color)
                )
                
                MetricCard(
                    title: "Ramp Rate",
                    value: String(format: "%+.1f", summary.rampRate),
                    subtitle: "TSS/week",
                    color: Color(summary.rampRateStatus.color)
                )
            }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Insights Section

struct TrainingLoadInsightsSection: View {
    let insights: [TrainingLoadInsight]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insights")
                .font(.headline)
            
            if insights.isEmpty {
                Text("You're on track! Keep up the balanced training.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            } else {
                ForEach(insights) { insight in
                    TrainingLoadInsightCard(insight: insight)
                }
            }
        }
    }
}

struct TrainingLoadInsightCard: View {
    let insight: TrainingLoadInsight
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: insight.icon)
                    .font(.title3)
                    .foregroundColor(Color(insight.priority.color))
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(insight.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            
            if isExpanded {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                        
                        Text("Recommendation")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    
                    Text(insight.recommendation)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}

// MARK: - Sync Status Banner

struct SyncStatusBanner: View {
    @ObservedObject var syncManager: TrainingLoadSyncManager
    let onSync: () -> Void
    
    var body: some View {
        if syncManager.needsSync || syncManager.lastSyncDate != nil {
            HStack(spacing: 12) {
                Image(systemName: syncManager.needsSync ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundColor(syncManager.needsSync ? .orange : .green)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(syncManager.needsSync ? "Sync Needed" : "Synced")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    if let lastSync = syncManager.lastSyncDate {
                        Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if syncManager.needsSync {
                    Button(action: onSync) {
                        Text("Sync Now")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange)
                            .cornerRadius(8)
                    }
                    .disabled(syncManager.isSyncing)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

// MARK: - View Model

@MainActor
class TrainingLoadViewModel: ObservableObject {
    @Published var summary: TrainingLoadSummary?
    @Published var dailyLoads: [DailyTrainingLoad] = []
    @Published var insights: [TrainingLoadInsight] = []
    
    private let manager = TrainingLoadManager.shared
    
    func refresh() {
        summary = manager.getCurrentSummary()
        dailyLoads = manager.getDailyLoads(for: .month)
        insights = manager.getInsights()
    }
    
    func loadPeriod(_ period: TrainingLoadPeriod) {
        dailyLoads = manager.getDailyLoads(for: period)
    }
}
