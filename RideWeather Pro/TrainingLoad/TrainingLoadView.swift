//
//  TrainingLoadView.swift
//  RideWeather Pro
//
//  Main training load tracking interface with multi-source support
//

import SwiftUI
import Charts
import Combine

struct TrainingLoadView: View {
    @StateObject private var viewModel = TrainingLoadViewModel()
    @StateObject private var trainingSync = UnifiedTrainingLoadSync()
    @StateObject private var wellnessSync = UnifiedWellnessSync()
    @StateObject private var wellnessManager = WellnessManager.shared
    @StateObject private var aiInsightsManager = AIInsightsManager()
    
    // Observe DataSourceManager to show current sources
    @ObservedObject private var dataSourceManager = DataSourceManager.shared
    
    @EnvironmentObject private var stravaService: StravaService
    @EnvironmentObject private var garminService: GarminService
    @EnvironmentObject private var weatherViewModel: WeatherViewModel
    @EnvironmentObject private var healthManager: HealthKitManager
    
    @State private var selectedPeriod: TrainingLoadPeriod = .month
    @State private var showingExplanation = false
    @State private var showingAIDebug = false
    
    @State private var hasPerformedInitialLoad = false
    @State private var wellnessUpdateTask: Task<Void, Never>?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // MARK: - NEW: Data Sources Header Card
                    // Clearly shows what is powering Training Load vs Wellness
                    DataSourceHeader(
                        trainingSource: dataSourceManager.configuration.trainingLoadSource,
                        wellnessSource: dataSourceManager.configuration.wellnessSource
                    )
                    
                    if let summary = viewModel.summary {
                        // Sync Status Banner
                        if stravaService.isAuthenticated || garminService.isAuthenticated || healthManager.isAuthorized {
                            EnhancedSyncStatusBanner(
                                trainingSync: trainingSync,
                                wellnessSync: wellnessSync,
                                trainingDaysCount: viewModel.totalDaysInStorage,
                                wellnessDaysCount: wellnessManager.dailyMetrics.count,
                                onTrainingSync: {
                                    Task {
                                        await syncBothTrainingAndWellness()
                                    }
                                },
                                onWellnessSync: {
                                    Task {
                                        await wellnessSync.syncFromConfiguredSource(
                                            healthManager: healthManager,
                                            garminService: garminService,
                                            days: 7
                                        )
                                    }
                                }
                            )
                        }
                        
                        // Current Status Card
                        CurrentFormCard(summary: summary)
                        
                        // Daily Readiness Card
                        if healthManager.isAuthorized && (viewModel.readiness?.latestHRV != nil || viewModel.readiness?.latestRHR != nil || viewModel.readiness?.sleepDuration != nil || viewModel.readiness?.averageHRV != nil) {
                            DailyReadinessCard(readiness: viewModel.readiness!)
                                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                        }
                        
                        // Daily Wellness Card
                        if let latestWellness = wellnessManager.dailyMetrics.last {
                            DailyWellnessCard(metrics: latestWellness)
                                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                        }
                        
                        // Recovery Status Card 
                        if let recovery = calculateRecoveryStatus(),
                           let wellness = wellnessManager.dailyMetrics.last {
                            RecoveryStatusCard(recovery: recovery, wellness: wellness)
                                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                        }

                        // Combined Insights (Training + Wellness)
                        let combinedInsights = wellnessManager.getCombinedInsights(trainingLoadSummary: summary)
                        if !combinedInsights.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Health & Training Insights")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                ForEach(combinedInsights) { insight in
                                    CombinedInsightCard(insight: insight)
                                }
                            }
                        }
                        
                        // AI Insights
                        if aiInsightsManager.isLoading {
                            AIInsightLoadingCard()
                                .transition(.opacity)
                        } else if let aiInsight = aiInsightsManager.currentInsight {
                            AIInsightCard(insight: aiInsight)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity
                                ))
                        }
                        
                        // Wellness Summary
                        if let wellnessSummary = wellnessManager.currentSummary {
                            WellnessSummaryCard(summary: wellnessSummary)
                        }
                        
                        // Full History Sync Button
                        if (stravaService.isAuthenticated || garminService.isAuthenticated || healthManager.isAuthorized) && viewModel.totalDaysInStorage < 200 {
                            Button {
                                Task {
                                    let startDate = Calendar.current.date(byAdding: .day, value: -365, to: Date())
                                    await syncBothTrainingAndWellness(startDate: startDate)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                    Text("Sync Full History (Last Year)")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    LinearGradient(
                                        colors: [.orange, .red],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                            }
                            .disabled(trainingSync.isSyncing || wellnessSync.isSyncing)

                            Text("You have \(viewModel.totalDaysInStorage) days of data. Sync more to see long-term trends.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        // Insights
                        TrainingLoadInsightsSection(insights: viewModel.insights)
                        
                        // Training Load Chart
                        TrainingLoadChart(
                            dailyLoads: viewModel.dailyLoads,
                            period: selectedPeriod
                        )
                        
                        // Period Selector
                        periodSelector
                        
                        // Key Metrics
                        MetricsGrid(summary: summary)
                        
                        // Wellness Trends Chart
                        if !wellnessManager.dailyMetrics.isEmpty {
                            WellnessTrendChart(
                                metrics: wellnessManager.dailyMetrics
                            )
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                        }
                        
                    } else {
                        // Empty states
                        if !healthManager.isAuthorized && !stravaService.isAuthenticated && !garminService.isAuthenticated {
                            emptyStateView
                        } else if healthManager.isAuthorized && !stravaService.isAuthenticated && !garminService.isAuthenticated {
                            healthOnlyEmptyState
                        } else {
                            emptyStateView
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Fitness & Wellness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if (stravaService.isAuthenticated || garminService.isAuthenticated) && !trainingSync.isSyncing {
                        Menu {
                            Button {
                                Task {
                                    let startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())
                                    await syncBothTrainingAndWellness(startDate: startDate)
                                }
                            } label: {
                                Label("Last 30 Days", systemImage: "calendar")
                            }
                            
                            Button {
                                Task {
                                    let startDate = Calendar.current.date(byAdding: .day, value: -90, to: Date())
                                    await syncBothTrainingAndWellness(startDate: startDate)
                                }
                            } label: {
                                Label("Last 90 Days", systemImage: "calendar")
                            }
                            
                            Button {
                                Task {
                                    let startDate = Calendar.current.date(byAdding: .day, value: -365, to: Date())
                                    await syncBothTrainingAndWellness(startDate: startDate)
                                }
                            } label: {
                                Label("Last Year", systemImage: "calendar.badge.clock")
                            }
                            
                            Divider()
                            
                            Button {
                                Task {
                                    await syncBothTrainingAndWellness()
                                }
                            } label: {
                                Label("Incremental Sync", systemImage: "arrow.triangle.2.circlepath")
                            }
                        } label: {
                            Label("Sync", systemImage: trainingSync.needsSync ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                                .foregroundColor(trainingSync.needsSync ? .orange : .blue)
                        }
                    }
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showingExplanation = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .overlay {
                if trainingSync.isSyncing {
                    ProcessingOverlay.syncing("Training Data", subtitle: trainingSync.syncStatus)
                        .zIndex(100)
                }
                if wellnessSync.isSyncing {
                    ProcessingOverlay.syncing("Wellness Data", subtitle: wellnessSync.syncStatus)
                        .zIndex(100)
                }
            }
            .animatedBackground(
                gradient: .rideAnalysisBackground,
                showDecoration: true,
                decorationColor: .white,
                decorationIntensity: 0.06
            )
            .sheet(isPresented: $showingExplanation) {
                TrainingLoadExplanationView()
            }
            .sheet(isPresented: $showingAIDebug) {
                AIInsightsDebugView(manager: aiInsightsManager)
            }
            .onAppear {
                // ONLY do this once per app session
                guard !hasPerformedInitialLoad else {
                    print("📊 TrainingLoadView: Skipping redundant onAppear refresh")
                    return
                }
                
                hasPerformedInitialLoad = true
                
                trainingSync.loadSyncDate()
                wellnessSync.loadSyncDate()
                
                // Force reload data from disk on appear to fix stale charts
                viewModel.refresh(readiness: healthManager.readiness)
                viewModel.loadPeriod(selectedPeriod, forceReload: true)
                
                Task {
                    // Sync training load if needed
                    if trainingSync.needsSync && (stravaService.isAuthenticated || garminService.isAuthenticated || healthManager.isAuthorized) {
                        await syncBothTrainingAndWellness()
                    }
                    
                    // Wellness will be synced above, but if ONLY wellness needs sync, do it separately
                    if !trainingSync.needsSync && wellnessSync.needsSync && (healthManager.isAuthorized || garminService.isAuthenticated) {
                        await wellnessSync.syncFromConfiguredSource(
                            healthManager: healthManager,
                            garminService: garminService,
                            days: 7
                        )
                    }
                    
                    // Generate AI insights with wellness data
                    await aiInsightsManager.analyzeWithWellness(
                        summary: viewModel.summary,
                        readiness: healthManager.readiness,
                        recentLoads: viewModel.dailyLoads,
                        wellnessMetrics: wellnessManager.dailyMetrics
                    )
                }
            }
            .onChange(of: selectedPeriod) { oldValue, newValue in
                viewModel.loadPeriod(newValue)
            }
            // DEBOUNCED wellness update: Only refresh after updates settle
            .onReceive(wellnessManager.$dailyMetrics) { newMetrics in
                // Cancel any pending update
                wellnessUpdateTask?.cancel()
                
                // Schedule a new update after 0.5 seconds of no changes
                wellnessUpdateTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                    guard !Task.isCancelled else { return }
                    
                    // Wellness data changed (steps, activity, etc.)
                    // Update wellness insights WITHOUT re-fetching sleep/HRV from HealthKit
                    print("📊 TrainingLoadView: Wellness metrics updated (\(newMetrics.count) days)")
                    
                    // Only update the summary and insights, don't re-fetch readiness
                    await MainActor.run {
                        viewModel.updateSummaryOnly()
                    }
                }
            }
            // THROTTLE the readiness change listener
            .onChange(of: healthManager.readiness) { newValue in
                // Only refresh if readiness actually changed meaningfully
                guard let lastReadiness = viewModel.readiness else {
                    // First time, always refresh
                    print("📊 TrainingLoadView: Initial readiness load")
                    viewModel.refresh(readiness: newValue)
                    return
                }
                
                guard lastReadiness.latestHRV != newValue.latestHRV ||
                      lastReadiness.latestRHR != newValue.latestRHR ||
                      lastReadiness.sleepDuration != newValue.sleepDuration else {
                    print("📊 TrainingLoadView: Readiness unchanged, skipping refresh")
                    return
                }
                
                print("📊 TrainingLoadView: Readiness changed, refreshing")
                viewModel.refresh(readiness: newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: .dataSourceChanged)) { _ in
                Task {
                    // Re-sync from new source (both training AND wellness)
                    await syncBothTrainingAndWellness(
                        startDate: Calendar.current.date(byAdding: .day, value: -90, to: Date())
                    )
                }
            }
        }
    }
    
    // MARK: - Period Selector
    
    private var periodSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(TrainingLoadPeriod.allPeriods, id: \.days) { period in
                    PeriodButton(
                        period: period,
                        isSelected: selectedPeriod.days == period.days,
                        action: {
                            if selectedPeriod.days != period.days {
                                selectedPeriod = period
                                viewModel.loadPeriod(period)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
    
    struct PeriodButton: View {
        let period: TrainingLoadPeriod
        let isSelected: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Text(period.name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .white : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.blue : Color(.systemGray6))
                    )
            }
        }
    }
    
    // MARK: - Empty States
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 70))
                .foregroundColor(.secondary)
            
            Text("No Training Data Yet")
                .font(.title2)
                .fontWeight(.bold)
            
            if stravaService.isAuthenticated || garminService.isAuthenticated {
                Text("Sync your activities to start tracking your fitness, fatigue, and form over time.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Button {
                    Task {
                        let startDate = Calendar.current.date(byAdding: .day, value: -365, to: Date())
                        await syncBothTrainingAndWellness(startDate: startDate)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync Activities")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .disabled(trainingSync.isSyncing || wellnessSync.isSyncing)

                if let lastSync = trainingSync.lastSyncDate {
                    Text("Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Connect to Strava, Garmin, or Apple Health in Settings to automatically track your training load.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Text("Connect in Settings → Data Sources")
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
    
    private var healthOnlyEmptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 70))
                .foregroundColor(.red)
            
            Text("Health Data Connected!")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Connect to Strava or Garmin in Settings to combine your physiological readiness with training load metrics for powerful insights.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Text("Configure in Settings → Data Sources")
                .font(.subheadline)
                .foregroundColor(.blue)
                .padding(.top, 8)
            
            Spacer()
        }
    }
  
    // MARK: - Helper Methods

    /// Syncs both training load AND wellness data together
    private func syncBothTrainingAndWellness(startDate: Date? = nil) async {
        // 1. Sync Training Load
        await trainingSync.syncFromConfiguredSource(
            stravaService: stravaService,
            garminService: garminService,
            healthManager: healthManager,
            userFTP: Double(weatherViewModel.settings.functionalThresholdPower),
            userLTHR: nil,
            startDate: startDate
        )
        
        // 2. Sync Wellness Data (ADDED)
        await wellnessSync.syncFromConfiguredSource(
            healthManager: healthManager,
            garminService: garminService,
            days: startDate == nil ? 7 : abs(Calendar.current.dateComponents([.day], from: startDate!, to: Date()).day ?? 7)
        )
        
        // 3. Refresh UI
        viewModel.refresh(readiness: healthManager.readiness)
        viewModel.loadPeriod(selectedPeriod, forceReload: true)
        
        print("✅ Synced both Training Load AND Wellness data")
    }
    
    // MARK: - Recovery Calculation Helper

    private func calculateRecoveryStatus() -> RecoveryStatus? {
        guard let wellness = wellnessManager.dailyMetrics.last else { return nil }
        
        let trainingHistory = viewModel.dailyLoads.filter { $0.rideCount > 0 }
        let lastWorkoutDate = trainingHistory.sorted { $0.date > $1.date }.first?.date
        
        let currentHRV = healthManager.readiness.latestHRV ?? Double(wellness.restingHeartRate ?? 60)
        let baselineHRV = healthManager.readiness.averageHRV ?? currentHRV
        let currentRHR = healthManager.readiness.latestRHR ?? Double(wellness.restingHeartRate ?? 60)
        let baselineRHR = healthManager.readiness.averageRHR ?? currentRHR
        
        let recovery = RecoveryStatus.calculate(
            lastWorkoutDate: lastWorkoutDate,
            currentHRV: currentHRV,
            baselineHRV: baselineHRV,
            currentRestingHR: currentRHR,
            baselineRestingHR: baselineRHR,
            wellness: wellness,
            weekHistory: wellnessManager.dailyMetrics
        )
        
        // Send to Watch
        PhoneSessionManager.shared.updateRecovery(recovery)
        
        return recovery
    }
}

struct CardHeaderWithInfo: View {
    let title: String
    let infoTitle: String
    let infoMessage: String
    @State private var showingInfo = false
    
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                        Button {
                showingInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .alert(infoTitle, isPresented: $showingInfo) {
            Button("Got It", role: .cancel) { }
        } message: {
            Text(infoMessage)
        }
    }
}

// MARK: - NEW: Data Source Header Card

struct DataSourceHeader: View {
    let trainingSource: DataSourceConfiguration.TrainingLoadSource
    let wellnessSource: DataSourceConfiguration.WellnessSource
    
    var body: some View {
        HStack(spacing: 16) {
            // Training Source
            HStack(spacing: 8) {
                sourceIcon(for: trainingSource.icon)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Training")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    Text(trainingSource.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
                .frame(height: 24)
            
            // Wellness Source
            HStack(spacing: 8) {
                sourceIcon(for: wellnessSource.icon, isWellness: true)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wellness")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    Text(wellnessSource.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    @ViewBuilder
    func sourceIcon(for iconName: String, isWellness: Bool = false) -> some View {
        if iconName.contains("_logo") {
            Image(iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: iconName)
                .font(.system(size: 18))
                .foregroundColor(isWellness ? .red : .red) //is not wellness was .blue
        }
    }
}

// MARK: - Enhanced Sync Status Banner

struct EnhancedSyncStatusBanner: View {
    @ObservedObject var trainingSync: UnifiedTrainingLoadSync
    @ObservedObject var wellnessSync: UnifiedWellnessSync

    let trainingDaysCount: Int
    let wellnessDaysCount: Int

    let onTrainingSync: () -> Void
    let onWellnessSync: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Training Load Sync Status
            if trainingSync.lastSyncDate != nil || trainingSync.needsSync {
                syncStatusRow(
                    needsSync: trainingSync.needsSync,
                    title: trainingSync.needsSync ? "Training Load Sync Needed" : "Training Load Synced",
                    lastSync: trainingSync.lastSyncDate,
                    daysCount: trainingDaysCount,
                    buttonColor: .orange,
                    onSync: onTrainingSync,
                    isSyncing: trainingSync.isSyncing
                )
            }
            
            // Wellness Sync Status
            if wellnessSync.lastSyncDate != nil || wellnessSync.needsSync {
                syncStatusRow(
                    needsSync: wellnessSync.needsSync,
                    title: wellnessSync.needsSync ? "Wellness Sync Needed" : "Wellness Synced",
                    lastSync: wellnessSync.lastSyncDate,
                    daysCount: wellnessDaysCount,
                    buttonColor: .red,
                    onSync: onWellnessSync,
                    isSyncing: wellnessSync.isSyncing
                )
            }
        }
    }
    
    private func syncStatusRow(
        needsSync: Bool,
        title: String,
        lastSync: Date?,
        daysCount: Int,
        buttonColor: Color,
        onSync: @escaping () -> Void,
        isSyncing: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: needsSync ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(needsSync ? .orange : .green)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if let lastSync = lastSync {
                    Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))\n\(daysCount) days loaded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if needsSync {
                Button(action: onSync) {
                    Text("Sync")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(buttonColor)
                        .cornerRadius(8)
                }
                .disabled(isSyncing)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
    
    // 1. Get the full X-axis domain (historical + future)
    private var xDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let defaultStart = calendar.date(byAdding: .day, value: -period.days, to: today)!
        let defaultEnd = calendar.date(byAdding: .day, value: 14, to: today)!
        
        guard !dailyLoads.isEmpty, let firstDate = dailyLoads.first?.date, let lastDate = dailyLoads.last?.date else {
            return defaultStart...defaultEnd
        }
        // Ensure the domain includes the full period AND the projection
        let startDate = min(defaultStart, firstDate)
        let endDate = max(defaultEnd, lastDate)
        return startDate...endDate
    }
    
    // 2. Prepare the two separate data series
    private var historicalData: [DailyTrainingLoad] {
        dailyLoads.filter { !$0.isProjected }
    }
    
    private var projectedData: [DailyTrainingLoad] {
        // We must include the *last* historical point to "connect" the dashed line
        let lastHistorical = historicalData.last
        let futureData = dailyLoads.filter { $0.isProjected }
        
        if let lastHistorical {
            // Only add if it's not already in the future data (which it shouldn't be)
            if !futureData.contains(where: { $0.id == lastHistorical.id }) {
                return [lastHistorical] + futureData
            }
        }
        return futureData
    }
    
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
                    // Zero reference line
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(.gray.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    
                    // --- 3. Draw Historical (Solid) Lines ---
                    // These use the "base" series names: "CTL", "ATL", "TSB"
                    ForEach(historicalData) { load in
                        if let ctl = load.ctl {
                            LineMark(
                                x: .value("Date", load.date),
                                y: .value("CTL", ctl)
                            )
                            .foregroundStyle(by: .value("Type", "CTL"))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 3)) // Solid
                        }
                        if let atl = load.atl {
                            LineMark(
                                x: .value("Date", load.date),
                                y: .value("ATL", atl)
                            )
                            .foregroundStyle(by: .value("Type", "ATL"))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2)) // Solid
                        }
                        if let tsb = load.tsb {
                            LineMark(
                                x: .value("Date", load.date),
                                y: .value("TSB", tsb)
                            )
                            .foregroundStyle(by: .value("Type", "TSB"))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2)) // Solid
                        }
                    }
                    
                    // --- 4. Draw Projected (Dashed) Lines ---
                    // These use *unique* series names: "CTL_Projected", etc.
                    ForEach(projectedData) { load in
                        if let ctl = load.ctl {
                            LineMark(
                                x: .value("Date", load.date),
                                y: .value("CTL", ctl)
                            )
                            .foregroundStyle(by: .value("Type", "CTL_Projected")) // <-- UNIQUE NAME
                            .interpolationMethod(.catmullRom)
                            // --- THINNER LINE ---
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4])) // Dashed, thinner (was 3)
                        }
                        if let atl = load.atl {
                            LineMark(
                                x: .value("Date", load.date),
                                y: .value("ATL", atl)
                            )
                            .foregroundStyle(by: .value("Type", "ATL_Projected")) // <-- UNIQUE NAME
                            .interpolationMethod(.catmullRom)
                            // --- THINNER LINE ---
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4])) // Dashed, thinner (was 2)
                        }
                        if let tsb = load.tsb {
                            LineMark(
                                x: .value("Date", load.date),
                                y: .value("TSB", tsb)
                            )
                            .foregroundStyle(by: .value("Type", "TSB_Projected")) // <-- UNIQUE NAME
                            .interpolationMethod(.catmullRom)
                            // --- THINNER LINE ---
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4])) // Dashed, thinner (was 2)
                        }
                    }
                }
                .chartXScale(domain: xDomain) // Use the full domain
                // 5. Map all 6 series names to their correct colors
                .chartForegroundStyleScale([
                    "CTL": .blue,
                    "ATL": .orange,
                    "TSB": .green,
                    "CTL_Projected": .blue,    // <-- Map dashed to same color
                    "ATL_Projected": .orange, // <-- Map dashed to same color
                    "TSB_Projected": .green   // <-- Map dashed to same color
                ])
                .chartSymbolScale(range: []) // Hide symbols
                .chartLegend(.hidden)
                .frame(height: 250)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                // X-Axis (Label fix is retained)
                .chartXAxis {
                    let today = Calendar.current.startOfDay(for: Date())
                    
                    // Automatic grid lines and labels (all of them)
                    AxisMarks(preset: .automatic, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.white.opacity(0.2))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    
                    // Just a visual "Today" marker line - no label
                    AxisMarks(values: [today]) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 2)).foregroundStyle(.white.opacity(0.9))
                    }
                }
                
                // Custom legend
                HStack(spacing: 20) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.blue).frame(width: 8, height: 8)
                        Text("Fitness (CTL)").font(.caption)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                        Text("Fatigue (ATL)").font(.caption)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("Form (TSB)").font(.caption)
                    }
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        
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

// MARK: - View Model Enhancement

@MainActor
class TrainingLoadViewModel: ObservableObject {
    @Published var summary: TrainingLoadSummary?
    @Published var dailyLoads: [DailyTrainingLoad] = []
    @Published var insights: [TrainingLoadInsight] = []
    @Published var readiness: PhysiologicalReadiness?
    @Published var totalDaysInStorage: Int = 0
    
    private let manager = TrainingLoadManager.shared
    private var currentPeriodDays: Int = 0
    
    // ADD THIS: Cache the last readiness to prevent redundant processing
    private var lastProcessedReadiness: PhysiologicalReadiness?
    
    /// Updates only summary and insights without re-fetching HealthKit data
    func updateSummaryOnly() {
        // Use the cached readiness (don't re-query HealthKit)
        summary = manager.getCurrentSummary()
        insights = manager.getInsights(readiness: self.readiness)
        totalDaysInStorage = manager.loadAllDailyLoads().count
        
        print("📊 ViewModel: Updated summary without HealthKit refresh")
    }
    
    func refresh(readiness: PhysiologicalReadiness?) {
        // Skip if readiness hasn't meaningfully changed
        if let lastProcessed = lastProcessedReadiness,
           let current = readiness,
           lastProcessed.latestHRV == current.latestHRV &&
           lastProcessed.latestRHR == current.latestRHR &&
           lastProcessed.sleepDuration == current.sleepDuration {
            print("🔄 TrainingLoadViewModel: Readiness unchanged, skipping refresh")
            return
        }
        
        lastProcessedReadiness = readiness
        
        print("\n🔄 TrainingLoadViewModel: Refreshing with readiness data...")
        
        // 1. Start with Apple Health readiness (if any)
        var unifiedReadiness = readiness ?? PhysiologicalReadiness()
        print("   📱 HealthKit baseline: Sleep=\(String(format: "%.1f", (unifiedReadiness.sleepDuration ?? 0) / 3600))h, RHR=\(Int(unifiedReadiness.latestRHR ?? 0))")
        
        // 2. Check if we have Garmin wellness data configured
        let config = DataSourceManager.shared.configuration
        let isUsingGarmin = config.wellnessSource == .garmin
        
        if isUsingGarmin {
            print("   ⚙️ Wellness source is Garmin - checking for data...")
            
            // Get TODAY's wellness metrics from Garmin (if available)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            
            if let todayMetrics = WellnessManager.shared.dailyMetrics.first(where: {
                calendar.isDate($0.date, inSameDayAs: today)
            }) {
                print("   ✅ Found today's Garmin wellness data - OVERRIDING HealthKit")
                
                // OVERRIDE Sleep with Garmin data
                if let sleep = todayMetrics.totalSleep, sleep > 0 {
                    print("      🔄 Sleep: \(String(format: "%.1f", (unifiedReadiness.sleepDuration ?? 0) / 3600))h → \(String(format: "%.1f", sleep / 3600))h (Garmin)")
                    unifiedReadiness.sleepDuration = sleep
                } else {
                    print("      ℹ️ No Garmin sleep data for today")
                }
                
                // OVERRIDE RHR with Garmin data
                if let rhr = todayMetrics.restingHeartRate {
                    print("      🔄 RHR: \(Int(unifiedReadiness.latestRHR ?? 0)) → \(rhr) bpm (Garmin)")
                    unifiedReadiness.latestRHR = Double(rhr)
                } else {
                    print("      ℹ️ No Garmin RHR data for today")
                }
                
            } else {
                print("   ⚠️ No Garmin wellness data for today - falling back to HealthKit")
            }
            
            // 3. Calculate 7-day averages from Garmin data
            let last7Days = calendar.date(byAdding: .day, value: -7, to: today)!
            let recentMetrics = WellnessManager.shared.dailyMetrics.filter {
                $0.date >= last7Days && $0.date <= today
            }
            
            if !recentMetrics.isEmpty {
                print("   📊 Calculating 7-day averages from \(recentMetrics.count) days of Garmin data")
                
                // Average Sleep
                let sleeps = recentMetrics.compactMap { $0.totalSleep }.filter { $0 > 0 }
                if !sleeps.isEmpty {
                    let avgSleep = sleeps.reduce(0, +) / Double(sleeps.count)
                    print("      🔄 Avg Sleep: \(String(format: "%.1f", (unifiedReadiness.averageSleepDuration ?? 0) / 3600))h → \(String(format: "%.1f", avgSleep / 3600))h (Garmin)")
                    unifiedReadiness.averageSleepDuration = avgSleep
                }
                
                // Average RHR
                let rhrs = recentMetrics.compactMap { $0.restingHeartRate }
                if !rhrs.isEmpty {
                    let avgRHR = Double(rhrs.reduce(0, +)) / Double(rhrs.count)
                    print("      🔄 Avg RHR: \(Int(unifiedReadiness.averageRHR ?? 0)) → \(Int(avgRHR)) bpm (Garmin)")
                    unifiedReadiness.averageRHR = avgRHR
                }
            }
        } else {
            print("   📱 Wellness source is Apple Health - using HealthKit data only")
        }
        
        print("   ✅ Final unified readiness: Sleep=\(String(format: "%.1f", (unifiedReadiness.sleepDuration ?? 0) / 3600))h, RHR=\(Int(unifiedReadiness.latestRHR ?? 0))")
        
        // 4. Update the published properties
        self.readiness = unifiedReadiness
        summary = manager.getCurrentSummary()
        insights = manager.getInsights(readiness: unifiedReadiness)
        totalDaysInStorage = manager.loadAllDailyLoads().count
    }
    
    func loadPeriod(_ period: TrainingLoadPeriod, forceReload: Bool = false) {
        guard forceReload || currentPeriodDays != period.days else {
            print("📊 Chart: Period unchanged, skipping reload")
            return
        }
        
        currentPeriodDays = period.days
        
        let allLoads = manager.loadAllDailyLoads()
        let today = Calendar.current.startOfDay(for: Date())
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -period.days, to: today)!
        
        let historicalLoads = allLoads.filter { $0.date >= cutoffDate && $0.date <= today }
            .sorted { $0.date < $1.date }
            .filter { $0.ctl != nil && $0.atl != nil }
        
        let projectedLoads = manager.getProjectedLoads(for: 14)
        
        self.dailyLoads = historicalLoads + projectedLoads
        
        print("📊 Chart: Showing \(historicalLoads.count) historical days + \(projectedLoads.count) projected days")
    }
}

