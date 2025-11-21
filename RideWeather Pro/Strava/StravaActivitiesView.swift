//
//  StravaActivitiesView.swift
//  RideWeather Pro
//

import SwiftUI
import Combine
import CoreLocation

struct StravaActivitiesView: View {
    @EnvironmentObject var stravaService: StravaService
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    @StateObject private var viewModel = StravaActivitiesViewModel()
    @Environment(\.dismiss) private var dismiss
    
    @State private var importingId: Int? = nil // ✅ ADDED: For per-row loading

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.activities.isEmpty {
                    ProgressView("Loading activities...")
                } else if let error = viewModel.errorMessage {
                    errorView(error: error)
                } else if viewModel.activities.isEmpty {
                    emptyStateView
                } else {
                    activitiesList
                }
            }
            .navigationTitle("Strava Activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            // ✅ REMOVED: .sheet(isPresented: $viewModel.showingAnalysisImport)
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewAnalysisImported"))) { _ in
                dismiss()
            }
        }
        .onAppear {
            if viewModel.activities.isEmpty {
                viewModel.loadActivities(service: stravaService)
            }
        }
    }
    
    private var activitiesList: some View {
        List {
            ForEach(viewModel.activities) { activity in
                // ✅ CHANGED: Replaced .onTapGesture with a Button
                Button(action: {
                    guard activity.device_watts == true else {
                        // Optionally show an alert here
                        viewModel.errorMessage = "This activity does not have power data and cannot be analyzed."
                        return
                    }
                    importingId = activity.id
                    viewModel.importActivity(
                        service: stravaService,
                        weatherViewModel: weatherViewModel,
                        activity: activity, // Pass activity directly
                        onSuccess: {
                            importingId = nil
                            dismiss()
                        },
                        onFailure: {
                            importingId = nil
                            // Error message is already set by the view model
                        }
                    )
                }) {
                    HStack {
                        ActivityRow(activity: activity)
                            .environmentObject(weatherViewModel)
                        
                        Spacer()
                        
                        if importingId == activity.id {
                            ProgressView()
                                .frame(width: 20)
                        } else if activity.device_watts != true {
                            Image(systemName: "bolt.slash.fill")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.gray.opacity(0.5))
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                }
                .buttonStyle(.plain)
                // Disable all rows if importing, or just this one if it has no power
                .disabled(importingId != nil || activity.device_watts != true)
            }
            
            // ... (Your existing 'Load More' button/section) ...
            if viewModel.hasMorePages {
                Section {
                    Button(action: {
                        viewModel.loadMoreActivities(service: stravaService)
                    }) {
                        HStack {
                            Spacer()
                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Loading...")
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "arrow.down.circle")
                                    .font(.title3)
                                Text("Load More Activities")
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .disabled(viewModel.isLoadingMore)
                }
            } else if !viewModel.activities.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.title3)
                                .foregroundColor(.green)
                            Text("All activities loaded")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .refreshable {
            viewModel.loadActivities(service: stravaService)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bicycle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Activities Found")
                .font(.headline)
            Text("Your recent Strava rides will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            Text("Error Loading Activities")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                viewModel.loadActivities(service: stravaService)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct ActivityRow: View {
    let activity: StravaActivity
    @EnvironmentObject var weatherViewModel: WeatherViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(activity.name)
                    .font(.headline)
                    .opacity(activity.device_watts == true ? 1.0 : 0.4) // Dim if no power
                
                Spacer()
                
                if activity.device_watts == true {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }
            
            HStack(spacing: 16) {
                Label(activity.durationFormatted, systemImage: "clock")
                    .font(.caption)
                
                Label(
                    weatherViewModel.settings.units == .metric ?
                        String(format: "%.2f km", activity.distanceKm) :
                        String(format: "%.2f mi", activity.distanceMiles),
                    systemImage: "figure.outdoor.cycle"
                )
                    .font(.caption)
                
                if let watts = activity.average_watts, watts > 0 {
                    Label("\(Int(watts))W", systemImage: "bolt")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .foregroundColor(.secondary)
            .opacity(activity.device_watts == true ? 1.0 : 0.4) // Dim if no power
            
            if let date = activity.startDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .opacity(activity.device_watts == true ? 1.0 : 0.4) // Dim if no power
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Import Sheet
// ✅ DELETED: The `StravaImportSheet` and `InfoRow` structs are no longer needed.


// MARK: - View Model

@MainActor
class StravaActivitiesViewModel: ObservableObject {
    @Published var activities: [StravaActivity] = []
    // ✅ REMOVED: @Published var selectedActivity: StravaActivity?
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var errorMessage: String?
    // ✅ REMOVED: @Published var showingAnalysisImport = false
    @Published var isLoadingMore = false
    @Published var hasMorePages = true
    
     private var currentPage = 1
     private let perPage = 50
     
    func loadActivities(service: StravaService) {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        activities = []

        Task {
            do {
                let allActivities = try await service.fetchRecentActivities(page: currentPage, perPage: perPage)
                await MainActor.run {
                    // Filter for rides with GPS data
                    let rides = allActivities.filter {
                        ($0.type == "Ride") &&
                        ($0.trainer == nil || $0.trainer == false) &&
                        !$0.start_date_local.isEmpty
                    }
                    
                    self.activities = rides
                    self.hasMorePages = allActivities.count == perPage
                    self.isLoading = false
                    
                    print("📱 Loaded page \(self.currentPage): \(allActivities.count) total, \(rides.count) rides")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    func loadMoreActivities(service: StravaService) {
        guard !isLoadingMore && hasMorePages else {
            print("📱 Skipping load more: isLoadingMore=\(isLoadingMore), hasMorePages=\(hasMorePages)")
            return
        }
        
        print("📱 Loading more activities...")
        isLoadingMore = true
        errorMessage = nil
        currentPage += 1
        
        Task {
            do {
                let allActivities = try await service.fetchRecentActivities(page: currentPage, perPage: perPage)
                await MainActor.run {
                    let newRides = allActivities.filter {
                        ($0.type == "Ride") &&
                        ($0.trainer == nil || $0.trainer == false) &&
                        !$0.start_date_local.isEmpty
                    }
                    
                    self.activities.append(contentsOf: newRides)
                    self.hasMorePages = allActivities.count == perPage
                    self.isLoadingMore = false
                    
                    print("📱 Loaded page \(self.currentPage): Added \(newRides.count) rides (total: \(self.activities.count))")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoadingMore = false
                    self.currentPage -= 1
                }
            }
        }
    }

    // ✅ REMOVED: func selectActivity(...)

    // ✅ UPDATED: Function signature now takes activity and callbacks
    func importActivity(
        service: StravaService,
        weatherViewModel: WeatherViewModel,
        activity: StravaActivity,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping () -> Void
    ) {
        // ✅ REMOVED: guard let activity = selectedActivity else { return }
        
        isImporting = true
        errorMessage = nil
        
        Task {
            do {
                print("StravaImport: Starting import for activity \(activity.id)")
                
                // Fetch streams (second-by-second data)
                let streams = try await service.fetchActivityStreams(activityId: activity.id)
                print("StravaImport: Streams fetched successfully")
                
                // Verify we have power data
                guard let powerStream = streams.watts?.data, !powerStream.isEmpty else {
                    print("StravaImport: No power data found")
                    throw ImportError.noPowerData
                }
                
                print("StravaImport: Found \(powerStream.count) power data points")
                
                // Convert to FITDataPoint format
                let dataPoints = convertStreamsToDataPoints(activity: activity, streams: streams)
                
                // Verify we got valid data
                guard !dataPoints.isEmpty else {
                    print("StravaImport: Conversion failed - no data points")
                    throw ImportError.conversionFailed
                }
                
                print("StravaImport: Converted \(dataPoints.count) data points")
                
                let elapsedTime: TimeInterval
                let movingTime: TimeInterval

                if let timeData = streams.time?.data, !timeData.isEmpty {
                    elapsedTime = TimeInterval(timeData.last ?? 0)
                    print("StravaImport: Elapsed time from stream: \(elapsedTime)s")
                } else {
                    elapsedTime = TimeInterval(activity.elapsed_time)
                    print("StravaImport: Elapsed time from metadata: \(elapsedTime)s")
                }

                movingTime = TimeInterval(activity.moving_time)
                print("StravaImport: Moving time from activity: \(movingTime)s")
                print("StravaImport: Time difference: \(elapsedTime - movingTime)s stopped")
                
                // Analyze using existing analyzer
                let analyzer = RideFileAnalyzer(settings: weatherViewModel.settings) // ✅ PASS SETTINGS
                
                // 1. Generate graph data and avg HR from the parsed FIT points
                let (powerGraphData, hrGraphData, elevationGraphData) = analyzer.generateGraphData(dataPoints: dataPoints)
                let heartRates = dataPoints.compactMap { $0.heartRate }
                let averageHeartRate = heartRates.isEmpty ? nil : (Double(heartRates.reduce(0, +)) / Double(heartRates.count))
                
                var analysis = analyzer.analyzeRide(
                    dataPoints: dataPoints,
                    ftp: Double(weatherViewModel.settings.functionalThresholdPower),
                    weight: weatherViewModel.settings.bodyWeight,
                    plannedRide: nil,
                    isPreFiltered: true,
                    elapsedTimeOverride: elapsedTime,
                    movingTimeOverride: movingTime,
                    averageHeartRate: averageHeartRate,     // <-- ADDED
                    powerGraphData: powerGraphData,      // <-- ADDED
                    heartRateGraphData: hrGraphData,
                    elevationGraphData: elevationGraphData
                )
                
                // Update the ride name to match Strava activity name
                analysis = RideAnalysis(
                    id: analysis.id,
                    date: analysis.date,
                    rideName: activity.name,  // Use Strava activity name
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
                    averageHeartRate: averageHeartRate,     // <-- ADDED
                    powerGraphData: powerGraphData,      // <-- ADDED
                    heartRateGraphData: hrGraphData,
                    elevationGraphData: elevationGraphData
                )
                
                print("StravaImport: Analysis complete - Performance Score: \(analysis.performanceScore)")
                
                // Save analysis
                let storage = AnalysisStorageManager()
                storage.saveAnalysis(analysis)
                print("StravaImport: Analysis saved")
                
                await MainActor.run {
                    self.isImporting = false

                    // ✅ NEW: Clear the previous pacing plan when importing new route
                    weatherViewModel.clearAdvancedPlan()
                     
                    // Small delay to ensure sheet dismisses first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // Post notification to show the analysis
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NewAnalysisImported"),
                            object: analysis,
                            userInfo: ["source": "strava"]
                        )
                        print("StravaImport: Notification posted")
                    }
                    TrainingLoadManager.shared.addRide(analysis: analysis)
                    
                    print("StravaImport: Setting route display name to '\(activity.name)'")
                    weatherViewModel.routeDisplayName = activity.name
                    weatherViewModel.importedRouteDisplayName = activity.name

                    onSuccess() // ✅ Call success callback
                }
            } catch { // ✅ Handle all errors
                print("StravaImport Error: \(error.localizedDescription)")
                await MainActor.run {
                    // Set specific error messages
                    if let importError = error as? ImportError {
                        self.errorMessage = importError.errorDescription
                    } else if let stravaError = error as? StravaService.StravaError {
                        self.errorMessage = stravaError.errorDescription
                    } else {
                        self.errorMessage = "Import failed: \(error.localizedDescription)"
                    }
                    self.isImporting = false
                    onFailure() // ✅ Call failure callback
                }
            }
        }
    }

    private func convertStreamsToDataPoints(activity: StravaActivity, streams: StravaStreams) -> [FITDataPoint] {
        guard let timeData = streams.time?.data,
              let powerData = streams.watts?.data else {
            return []
        }
        
        let startDate = activity.startDate ?? Date()
        var dataPoints: [FITDataPoint] = []
        
        let distanceData = streams.distance?.data
        let altitudeData = streams.altitude?.data
        let heartrateData = streams.heartrate?.data
        let cadenceData = streams.cadence?.data
        let speedData = streams.velocity_smooth?.data
        let latlngData = streams.latlng?.data
        let movingData = streams.moving?.data
        
        if let moving = movingData {
            let stoppedCount = moving.filter { !$0 }.count
            print("StravaImport: Moving stream has \(moving.count) points, \(stoppedCount) stopped")
        } else {
            print("StravaImport: ⚠️ NO MOVING STREAM - will include all points")
        }

        var skippedCount = 0
        for i in 0..<timeData.count {
            // ✅ UPDATED: Use a nil-coalescing check for movingData
            // If movingData is nil, we assume we are moving (isMoving = true)
            let isMoving = movingData?[safe: i] ?? true
            
            if !isMoving {
                skippedCount += 1
                continue
            }
            
            // ✅ FIX: Ensure powerData has an entry for this index
            guard let power = powerData[safe: i] else {
                // If power data is missing for this timestamp, skip the point
                skippedCount += 1
                continue
            }

            let timestamp = startDate.addingTimeInterval(timeData[i])
            let heartRate = heartrateData?[safe: i].map { Int($0) }
            let cadence = cadenceData?[safe: i].map { Int($0) }
            let speed = speedData?[safe: i]
            let distance = distanceData?[safe: i]
            let altitude = altitudeData?[safe: i]
            
            var coordinate: CLLocationCoordinate2D?
            if let latlng = latlngData?[safe: i], latlng.count == 2 {
                coordinate = CLLocationCoordinate2D(latitude: latlng[0], longitude: latlng[1])
            }
            
            dataPoints.append(FITDataPoint(
                timestamp: timestamp,
                power: power, // power is now non-optional here
                heartRate: heartRate,
                cadence: cadence,
                speed: speed,
                distance: distance,
                altitude: altitude,
                position: coordinate
            ))
        }
        
        print("StravaImport: Created \(dataPoints.count) data points, skipped \(skippedCount) points")
        
        return dataPoints
    }
    
    enum ImportError: LocalizedError {
        case noPowerData
        case conversionFailed
        
        var errorDescription: String? {
            switch self {
            case .noPowerData:
                return "This activity doesn't contain power data"
            case .conversionFailed:
                return "Failed to convert activity data to analysis format"
            }
        }
    }
}

/*// ✅ ADDED: Safe collection access
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}*/
