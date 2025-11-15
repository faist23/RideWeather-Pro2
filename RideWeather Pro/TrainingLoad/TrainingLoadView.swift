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
    @EnvironmentObject private var healthManager: HealthKitManager

    @State private var selectedPeriod: TrainingLoadPeriod = .month
    @State private var showingExplanation = false
    @StateObject private var aiInsightsManager = AIInsightsManager()

    @State private var showingAIDebug = false

  
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
                                        let startDate = viewModel.summary == nil
                                        ? Calendar.current.date(byAdding: .day, value: -365, to: Date())
                                        : nil
                                        
                                        await syncManager.syncFromStrava(
                                            stravaService: stravaService,
                                            userFTP: Double(weatherViewModel.settings.functionalThresholdPower),
                                            userLTHR: nil,
                                            startDate: startDate
                                        )
                                        viewModel.refresh(readiness: healthManager.readiness)
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
                        
                        // Full History Sync Button (if data is limited)
                        if stravaService.isAuthenticated && viewModel.totalDaysInStorage < 200 {
                            Button {
                                Task {
                                    let startDate = Calendar.current.date(byAdding: .day, value: -365, to: Date())
                                    await syncManager.syncFromStrava(
                                        stravaService: stravaService,
                                        userFTP: Double(weatherViewModel.settings.functionalThresholdPower),
                                        userLTHR: nil,
                                        startDate: startDate
                                    )
                                    viewModel.refresh(readiness: healthManager.readiness)
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
                            .disabled(syncManager.isSyncing)
                            
                            Text("You have \(viewModel.totalDaysInStorage) days of data. Sync more to see long-term trends.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
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
                        // Show empty state
                        if !healthManager.isAuthorized && !stravaService.isAuthenticated {
                            emptyStateView
                        } else if healthManager.isAuthorized && !stravaService.isAuthenticated {
                            stravaEmptyStateView
                        } else {
                            emptyStateView
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Fitness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // LEADING ITEM GROUP - Sync Menu
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if stravaService.isAuthenticated && !syncManager.isSyncing {
                        Menu {
                            Button {
                                Task {
                                    let startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())
                                    await syncManager.syncFromStrava(
                                        stravaService: stravaService,
                                        userFTP: Double(weatherViewModel.settings.functionalThresholdPower),
                                        userLTHR: nil,
                                        startDate: startDate
                                    )
                                    viewModel.refresh(readiness: healthManager.readiness)
                                }
                            } label: {
                                Label("Last 30 Days", systemImage: "calendar")
                            }
                            
                            Button {
                                Task {
                                    let startDate = Calendar.current.date(byAdding: .day, value: -90, to: Date())
                                    await syncManager.syncFromStrava(
                                        stravaService: stravaService,
                                        userFTP: Double(weatherViewModel.settings.functionalThresholdPower),
                                        userLTHR: nil,
                                        startDate: startDate
                                    )
                                    viewModel.refresh(readiness: healthManager.readiness)
                                }
                            } label: {
                                Label("Last 90 Days", systemImage: "calendar")
                            }
                            
                            Button {
                                Task {
                                    let startDate = Calendar.current.date(byAdding: .day, value: -365, to: Date())
                                    await syncManager.syncFromStrava(
                                        stravaService: stravaService,
                                        userFTP: Double(weatherViewModel.settings.functionalThresholdPower),
                                        userLTHR: nil,
                                        startDate: startDate
                                    )
                                    viewModel.refresh(readiness: healthManager.readiness)
                                }
                            } label: {
                                Label("Last Year (365 Days)", systemImage: "calendar.badge.clock")
                            }
                            
                            Divider()
                            
                            Button {
                                Task {
                                    await syncManager.syncFromStrava(
                                        stravaService: stravaService,
                                        userFTP: Double(weatherViewModel.settings.functionalThresholdPower),
                                        userLTHR: nil,
                                        startDate: nil
                                    )
                                    viewModel.refresh(readiness: healthManager.readiness)
                                }
                            } label: {
                                Label("Incremental Sync", systemImage: "arrow.triangle.2.circlepath")
                            }
                        } label: {
                            Label("Sync", systemImage: syncManager.needsSync ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                                .foregroundColor(syncManager.needsSync ? .orange : .blue)
                        }
                    } else {
                        Color.clear.frame(width: 0)
                    }
                }
                
                // TRAILING ITEM GROUP
                ToolbarItemGroup(placement: .navigationBarTrailing) {
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
                syncManager.loadSyncDate()
                viewModel.refresh(readiness: healthManager.readiness)
                viewModel.loadPeriod(selectedPeriod)
                
                Task {
                    if syncManager.needsSync && stravaService.isAuthenticated {
                        await syncManager.syncFromStrava(
                            stravaService: stravaService,
                            userFTP: Double(weatherViewModel.settings.functionalThresholdPower),
                            userLTHR: nil,
                            startDate: nil
                        )
                        viewModel.refresh(readiness: healthManager.readiness)
                        viewModel.loadPeriod(selectedPeriod)
                    }
                    
                    await aiInsightsManager.analyzeIfNeeded(
                        summary: viewModel.summary,
                        readiness: healthManager.readiness,
                        recentLoads: viewModel.dailyLoads
                    )
                }
            }
            .onChange(of: selectedPeriod) { oldValue, newValue in
                viewModel.loadPeriod(newValue)
            }
            .onChange(of: healthManager.readiness) {
                viewModel.refresh(readiness: healthManager.readiness)
            }
        }
    }

/*    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // --- REMOVED ConnectHealthCard ---
                    
                    if let summary = viewModel.summary {
                        // Sync Status Banner (if applicable)
                        if stravaService.isAuthenticated {
                            SyncStatusBanner(
                                syncManager: syncManager,
                                onSync: {
                                    Task {
                                        let startDate = viewModel.summary == nil
                                        ? Calendar.current.date(byAdding: .day, value: -365, to: Date())
                                        : nil
                                        
                                        await syncManager.syncFromStrava(
                                            stravaService: stravaService,
                                            userFTP: Double(weatherViewModel.settings.functionalThresholdPower),
                                            userLTHR: nil,
                                            startDate: startDate
                                        )
                                        viewModel.refresh(readiness: healthManager.readiness) // <-- Pass readiness
                                    }
                                }
                            )
                        }
                        
                        // Current Status Card
                        CurrentFormCard(summary: summary)
                        
                        // --- ADD DailyReadinessCard ---
                        if healthManager.isAuthorized && (viewModel.readiness?.latestHRV != nil || viewModel.readiness?.latestRHR != nil || viewModel.readiness?.sleepDuration != nil || viewModel.readiness?.averageHRV != nil) {
                            DailyReadinessCard(readiness: viewModel.readiness!)
                                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                        }
                        // ---
 
                        // AI Insights (NEW)
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
                        
/*                        // Add this somewhere visible in your TrainingLoadView body
                        // (I'd put it right after the DailyReadinessCard or AI insight cards)

                        // TEMPORARY TEST BUTTON - Remove once you're satisfied
                        if viewModel.summary != nil {
                            Button {
                                Task {
                                    await aiInsightsManager.forceAnalyze(
                                        summary: viewModel.summary,
                                        readiness: healthManager.readiness,
                                        recentLoads: viewModel.dailyLoads
                                    )
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text("Generate AI Insight")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    LinearGradient(
                                        colors: [.purple, .blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                            }
                            .disabled(aiInsightsManager.isLoading)
                            .opacity(aiInsightsManager.isLoading ? 0.6 : 1.0)
                        }
                        //------------------------romove if satisfied with ai output
 */
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
                        // Show empty state *unless* health is connected but Strava isn't
                        if !healthManager.isAuthorized && !stravaService.isAuthenticated {
                            emptyStateView
                        } else if healthManager.isAuthorized && !stravaService.isAuthenticated {
                            // Special empty state if only Health is connected
                            stravaEmptyStateView
                        } else {
                            emptyStateView // Default empty state
                        }
                    }
                }
/*                // Add this in the VStack after your other cards (around line 100)
                Button("🧪 Force AI Analysis") {
                    Task {
                        await aiInsightsManager.forceAnalyze(
                            summary: viewModel.summary,
                            readiness: healthManager.readiness,
                            recentLoads: viewModel.dailyLoads
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
 */
                .padding()
            }
            .navigationTitle("Fitness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // --- LEADING ITEM GROUP ---
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if stravaService.isAuthenticated && !syncManager.isSyncing {
                        Button {
                            Task {
                                let startDate = viewModel.summary == nil
                                ? Calendar.current.date(byAdding: .day, value: -90, to: Date())
                                : nil
                                
                                await syncManager.syncFromStrava(
                                    stravaService: stravaService,
                                    userFTP: Double(weatherViewModel.settings.functionalThresholdPower),
                                    userLTHR: nil,
                                    startDate: startDate
                                )
                                viewModel.refresh(readiness: healthManager.readiness)
                            }
                        } label: {
                            Label("Sync", systemImage: syncManager.needsSync ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                                .foregroundColor(syncManager.needsSync ? .orange : .blue)
                        }
                    } else {
                        // This is good practice for layout stability
                        Color.clear.frame(width: 0)
                    }
                }
                
                // --- TRAILING ITEM GROUP ---
                // Even with one button, this is a more stable structure
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showingExplanation = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    
                    // If you want to add your debug button back,
                    // you can safely add it *right here*.
                    
                    // Button {
                    //    showingAIDebug = true
                    // } label: {
                    //    Image(systemName: "dollarsign.circle")
                    // }
                }
            }
            .overlay {
                if syncManager.isSyncing {
                    syncingOverlay
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
                // The data is already being fetched by MainView.
                // We just need to load it into the view.
                syncManager.loadSyncDate()
                viewModel.refresh(readiness: healthManager.readiness)
                viewModel.loadPeriod(selectedPeriod)
                
                // We can still trigger the AI analysis and a Strava sync here
                Task {
                    // 1. Run Strava sync if needed
                    if syncManager.needsSync && stravaService.isAuthenticated {
                        await syncManager.syncFromStrava(
                            stravaService: stravaService,
                            userFTP: Double(weatherViewModel.settings.functionalThresholdPower),
                            userLTHR: nil,
                            startDate: nil
                        )
                        // 2. Refresh all data after sync
                        viewModel.refresh(readiness: healthManager.readiness)
                        viewModel.loadPeriod(selectedPeriod)
                    }
                    
                    // 3. Trigger AI analysis
                    await aiInsightsManager.analyzeIfNeeded(
                        summary: viewModel.summary,
                        readiness: healthManager.readiness,
                        recentLoads: viewModel.dailyLoads
                    )
                }
            }
            .onChange(of: selectedPeriod) { oldValue, newValue in
                viewModel.loadPeriod(newValue)
            }
            // Refresh insights when health data changes ---
            .onChange(of: healthManager.readiness) {
                viewModel.refresh(readiness: healthManager.readiness)
            }
        }
    }*/
    
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
                        let startDate = Calendar.current.date(byAdding: .day, value: -365, to: Date())
                        
                        await syncManager.syncFromStrava(
                            stravaService: stravaService,
                            userFTP: Double(weatherViewModel.settings.functionalThresholdPower),
                            userLTHR: nil,
                            startDate: startDate
                        )
                        
                        viewModel.refresh(readiness: healthManager.readiness) // Pass readiness
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
    
    // --- ADD THIS NEW EMPTY STATE ---
    private var stravaEmptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 70))
                .foregroundColor(.red)
            
            Text("Health Data Connected!")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Connect to Strava in Settings to combine your physiological readiness with your training load (TSS, CTL, ATL) for the most powerful insights.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Text("Connect in Settings → Strava")
                .font(.subheadline)
                .foregroundColor(.blue)
                .padding(.top, 8)
            
            Spacer()
        }
    }
}

/*// --- ADD THIS NEW VIEW ---
struct ConnectHealthCard: View {
    var onConnect: () -> Void
    var healthError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundColor(.red)
                
                VStack(alignment: .leading) {
                    Text("Connect to Apple Health")
                        .font(.headline.weight(.semibold))
                    Text("Get smarter readiness insights.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text("Allow access to HRV, Resting Heart Rate, and Sleep to get personalized recovery advice alongside your training load.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button {
                onConnect()
            } label: {
                Text("Connect Apple Health")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            
            if let error = healthError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}*/

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
                    
                    // Automatic grid lines and labels
                    AxisMarks(preset: .automatic, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.white.opacity(0.2))
                        
                        // Check if this value is 'Today' to avoid overlap
                        let isToday = Calendar.current.isDate(value.as(Date.self) ?? Date.distantPast, inSameDayAs: today)
                        
                        if !isToday {
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(.white.opacity(0.8))
                        } else {
                            // Draw an empty label to prevent overlap
                            AxisValueLabel()
                                .foregroundStyle(.clear)
                        }
                    }
                    
                    // Explicit "Today" marker
                    AxisMarks(values: [today]) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1.5)).foregroundStyle(.white.opacity(0.7))
                        AxisValueLabel("Today")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .offset(y: 3)
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
                    Button(action: onSync) {  // This already calls onSync which is passed in
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
    @Published var readiness: PhysiologicalReadiness?
    @Published var totalDaysInStorage: Int = 0
    
    private let manager = TrainingLoadManager.shared
    private var currentPeriodDays: Int = 0
    
    func refresh(readiness: PhysiologicalReadiness?) {
        self.readiness = readiness // Store the latest readiness
        summary = manager.getCurrentSummary()
        // Pass the latest readiness data when generating insights
        insights = manager.getInsights(readiness: readiness)
        totalDaysInStorage = manager.loadAllDailyLoads().count
    }
    
    func loadPeriod(_ period: TrainingLoadPeriod) {
        guard currentPeriodDays != period.days else {
            print("📊 Chart: Period unchanged, skipping reload")
            return
        }
        
        currentPeriodDays = period.days
        
        let allLoads = manager.loadAllDailyLoads()
        let today = Calendar.current.startOfDay(for: Date())
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -period.days, to: today)!
        
        // 1. Get historical data for the period
        let historicalLoads = allLoads.filter { $0.date >= cutoffDate && $0.date <= today }
            .sorted { $0.date < $1.date }
            .filter { $0.ctl != nil && $0.atl != nil } // Only include days with metrics
        
        // 2. Get projected data (14 days into the future)
        let projectedLoads = manager.getProjectedLoads(for: 14)
        
        // 3. Combine them
        self.dailyLoads = historicalLoads + projectedLoads
        
        print("📊 Chart: Showing \(historicalLoads.count) historical days + \(projectedLoads.count) projected days")
    }
}

