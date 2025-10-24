
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
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.activities.isEmpty {
                    ProgressView("Loading activities...")
                } else if let error = viewModel.errorMessage {
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
                } else if viewModel.activities.isEmpty {
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
                } else {
                    List {
                        ForEach(viewModel.activities) { activity in
                            ActivityRow(activity: activity)
                                .environmentObject(weatherViewModel)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectActivity(activity, service: stravaService, weatherViewModel: weatherViewModel)
                                }
                        }
                    }
                    .refreshable {
                        viewModel.loadActivities(service: stravaService)
                    }
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
            .sheet(isPresented: $viewModel.showingAnalysisImport) {
                if let activity = viewModel.selectedActivity {
                    StravaImportSheet(
                        activity: activity,
                        viewModel: viewModel,
                        stravaService: stravaService,
                        weatherViewModel: weatherViewModel
                    )
                }
            }
            // ✅ ADD THIS - Auto-dismiss when analysis is imported
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
}

struct ActivityRow: View {
    let activity: StravaActivity
    @EnvironmentObject var weatherViewModel: WeatherViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(activity.name)
                    .font(.headline)
                
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
                        String(format: "%.1f km", activity.distanceKm) :
                        String(format: "%.1f mi", activity.distanceMiles),
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
            
            if let date = activity.startDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Import Sheet

struct StravaImportSheet: View {
    let activity: StravaActivity
    @ObservedObject var viewModel: StravaActivitiesViewModel
    @ObservedObject var stravaService: StravaService
    @ObservedObject var weatherViewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if viewModel.isImporting {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Importing from Strava...")
                            .font(.headline)
                        Text("Fetching activity streams and analyzing performance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(activity.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            InfoRow(
                                label: "Distance",
                                value: weatherViewModel.settings.units == .metric ?
                                    String(format: "%.1f km", activity.distanceKm) :
                                    String(format: "%.1f mi", activity.distanceMiles)
                            )
                            InfoRow(label: "Duration", value: activity.durationFormatted)
                            
                            if let watts = activity.average_watts, watts > 0 {
                                InfoRow(label: "Avg Power", value: "\(Int(watts))W")
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("No power data available")
                                        .font(.subheadline)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        
                        if let error = viewModel.errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            viewModel.importActivity(service: stravaService, weatherViewModel: weatherViewModel)
                        }) {
                            HStack {
                                Image(systemName: "chart.xyaxis.line")
                                Text("Analyze This Ride")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(activity.device_watts == true ? Color.blue : Color.gray)
                            .cornerRadius(12)
                        }
                        .disabled(activity.device_watts != true)
                        
                        if activity.device_watts != true {
                            Text("Power data is required for ride analysis")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Import from Strava")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - View Model

@MainActor
class StravaActivitiesViewModel: ObservableObject {
    @Published var activities: [StravaActivity] = []
    @Published var selectedActivity: StravaActivity?
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var errorMessage: String?
    @Published var showingAnalysisImport = false
    
    func loadActivities(service: StravaService) {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let activities = try await service.fetchRecentActivities(limit: 60)
                await MainActor.run {
                    self.activities = activities
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    func selectActivity(_ activity: StravaActivity, service: StravaService, weatherViewModel: WeatherViewModel) {
        selectedActivity = activity
        showingAnalysisImport = true
    }
    
    func importActivity(service: StravaService, weatherViewModel: WeatherViewModel) {
        guard let activity = selectedActivity else { return }
        
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
                
                // Analyze using existing analyzer
                let analyzer = RideFileAnalyzer()
                var analysis = analyzer.analyzeRide(
                    dataPoints: dataPoints,
                    ftp: Double(weatherViewModel.settings.functionalThresholdPower),
                    weight: weatherViewModel.settings.bodyWeight,
                    plannedRide: nil
                )
                
                // Update the ride name to match Strava activity name
                analysis = RideAnalysis(
                    id: analysis.id,
                    date: analysis.date,
                    rideName: activity.name,  // Use Strava activity name
                    duration: analysis.duration,
                    distance: analysis.distance,
                    averagePower: analysis.averagePower,
                    normalizedPower: analysis.normalizedPower,
                    intensityFactor: analysis.intensityFactor,
                    trainingStressScore: analysis.trainingStressScore,
                    variabilityIndex: analysis.variabilityIndex,
                    peakPower5s: analysis.peakPower5s,
                    peakPower1min: analysis.peakPower1min,
                    peakPower5min: analysis.peakPower5min,
                    peakPower20min: analysis.peakPower20min,
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
                    powerZoneDistribution: analysis.powerZoneDistribution
                )
                
                print("StravaImport: Analysis complete - Performance Score: \(analysis.performanceScore)")
                
                // Save analysis
                let storage = AnalysisStorageManager()
                storage.saveAnalysis(analysis)
                print("StravaImport: Analysis saved")
                
                await MainActor.run {
                    self.isImporting = false
                    self.showingAnalysisImport = false
                    
                    // Small delay to ensure sheet dismisses first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // Post notification to show the analysis
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NewAnalysisImported"),
                            object: analysis
                        )
                        print("StravaImport: Notification posted")
                    }
                }
            } catch ImportError.noPowerData {
                print("StravaImport Error: No power data")
                await MainActor.run {
                    self.errorMessage = "This activity doesn't have power data"
                    self.isImporting = false
                }
            } catch ImportError.conversionFailed {
                print("StravaImport Error: Conversion failed")
                await MainActor.run {
                    self.errorMessage = "Failed to convert activity data"
                    self.isImporting = false
                }
            } catch let error as StravaService.StravaError {
                print("StravaImport Error: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isImporting = false
                }
            } catch {
                print("StravaImport Error: \(error)")
                await MainActor.run {
                    self.errorMessage = "Import failed: \(error.localizedDescription)"
                    self.isImporting = false
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
        
        // Get other streams if available
        let distanceData = streams.distance?.data
        let altitudeData = streams.altitude?.data
        let heartrateData = streams.heartrate?.data
        let cadenceData = streams.cadence?.data
        let speedData = streams.velocity_smooth?.data
        let latlngData = streams.latlng?.data
        
        // Process each time point
        for i in 0..<timeData.count {
            let timestamp = startDate.addingTimeInterval(timeData[i])
            let power = powerData[safe: i]
            let heartRate = heartrateData?[safe: i].map { Int($0) }
            let cadence = cadenceData?[safe: i].map { Int($0) }
            let speed = speedData?[safe: i]
            let distance = distanceData?[safe: i]
            let altitude = altitudeData?[safe: i]
            
            // Parse coordinates if available
            var coordinate: CLLocationCoordinate2D?
            if let latlng = latlngData?[safe: i], latlng.count == 2 {
                coordinate = CLLocationCoordinate2D(latitude: latlng[0], longitude: latlng[1])
            }
            
            dataPoints.append(FITDataPoint(
                timestamp: timestamp,
                power: power,
                heartRate: heartRate,
                cadence: cadence,
                speed: speed,
                distance: distance,
                altitude: altitude,
                position: coordinate
            ))
        }
        
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
