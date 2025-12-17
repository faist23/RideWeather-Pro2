//
//  GarminActivityImportView.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 12/8/25.
//

import CoreLocation
import SwiftUI

struct GarminActivityImportView: View {
    @EnvironmentObject var garminService: GarminService
    @EnvironmentObject var rideViewModel: RideAnalysisViewModel
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var activities: [GarminActivitySummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    
    // Track which specific row is currently importing
    @State private var importingId: Int? = nil
    
    var filteredActivities: [GarminActivitySummary] {
        if searchText.isEmpty {
            return activities
        }
        return activities.filter {
            ($0.activityName ?? "").localizedCaseInsensitiveContains(searchText) ||
            $0.activityType.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Main List
                Group {
                    if isLoading && activities.isEmpty {
                        ProgressView("Loading Garmin activities...")
                    } else if let error = errorMessage {
                        errorView(error: error)
                    } else if activities.isEmpty {
                        emptyStateView
                    } else {
                        activitiesList
                    }
                }
            }
            .navigationTitle("Garmin Activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if activities.isEmpty {
                    await loadActivities()
                }
            }
        }
    }
    
    private var activitiesList: some View {
        List {
            ForEach(filteredActivities) { activity in
                Button(action: {
                    // Start import
                    handleImport(for: activity)
                }) {
                    HStack {
                        GarminActivityRow(activity: activity)
                            .environmentObject(weatherViewModel)
                        
                        Spacer()
                        
                        if importingId == activity.id {
                            ProgressView()
                                .frame(width: 20)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(importingId != nil) // Disable interaction while any import is running
            }
        }
        .searchable(text: $searchText, prompt: "Search activities")
        .refreshable {
            await loadActivities()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No Activities Found")
                .font(.headline)
            Text("Complete cycling activities in Garmin Connect to import them here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            Text("Unable to load activities")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await loadActivities() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    // MARK: - Logic
    
    private func loadActivities() async {
        isLoading = true
        errorMessage = nil
        
        do {
            activities = try await garminService.fetchRecentActivities(limit: 50)
            if activities.isEmpty {
                // Keep empty list, view handles empty state
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func handleImport(for activity: GarminActivitySummary) {
        importingId = activity.id
        
        Task {
            do {
                // Fetch full activity details with GPS samples
                let activityDetail = try await garminService.fetchActivityDetails(activityId: activity.activityId)
                
                // Convert to your app's format
                let rideData = convertToRideData(activityDetail)
                
                await MainActor.run {
                    // Import into ride analysis
                    rideViewModel.importRideData(rideData)
                    
                    // Send notification
                    if let currentAnalysis = rideViewModel.currentAnalysis {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NewAnalysisImported"),
                            object: currentAnalysis,
                            userInfo: ["source": "garmin"]
                        )
                    }
                    
                    importingId = nil
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    // Update error message to inform user, then clear loading state
                    errorMessage = "Failed to import: \(error.localizedDescription)"
                    importingId = nil
                }
            }
        }
    }
    
    private func convertToRideData(_ activity: GarminActivityDetail) -> ImportedRideData {
        var gpsPoints: [GPSPoint] = []
        var powerData: [PowerDataPoint] = []
        var heartRateData: [HeartRateDataPoint] = []
        
        if let samples = activity.samples {
            var cumulativeDistance: Double = 0
            var previousLocation: (lat: Double, lon: Double)? = nil
            
            for sample in samples {
                let timestamp = Date(timeIntervalSince1970: TimeInterval(sample.startTimeInSeconds))
                
                // Calculate distance
                if let lat = sample.latitude, let lon = sample.longitude {
                    if let prevLoc = previousLocation {
                        let loc1 = CLLocation(latitude: prevLoc.lat, longitude: prevLoc.lon)
                        let loc2 = CLLocation(latitude: lat, longitude: lon)
                        cumulativeDistance += loc1.distance(from: loc2)
                    }
                    previousLocation = (lat, lon)
                    
                    gpsPoints.append(GPSPoint(
                        timestamp: timestamp,
                        latitude: lat,
                        longitude: lon,
                        elevation: sample.elevation,
                        speed: sample.speed,
                        distance: cumulativeDistance
                    ))
                }
                
                // Power
                let powerValue = sample.power ?? 0.0
                powerData.append(PowerDataPoint(timestamp: timestamp, watts: powerValue))
                
                // Heart rate
                if let hr = sample.heartRate, hr > 0 {
                    heartRateData.append(HeartRateDataPoint(timestamp: timestamp, bpm: hr))
                }
            }
        }
        
        return ImportedRideData(
            activityName: activity.activityName ?? "Garmin Ride",
            startTime: Date(timeIntervalSince1970: TimeInterval(activity.startTimeInSeconds)),
            duration: TimeInterval(activity.durationInSeconds),
            distance: activity.distanceInMeters ?? 0,
            gpsPoints: gpsPoints,
            powerData: powerData,
            heartRateData: heartRateData,
            averagePower: activity.averagePowerInWatts,
            normalizedPower: activity.normalizedPowerInWatts,
            averageHeartRate: activity.averageHeartRateInBeatsPerMinute,
            maxHeartRate: activity.maxHeartRateInBeatsPerMinute,
            elevationGain: activity.elevationGainInMeters,
            elevationLoss: activity.elevationLossInMeters,
            calories: activity.activeKilocalories
        )
    }
}

struct GarminActivityRow: View {
    let activity: GarminActivitySummary
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(activity.activityName ?? "Garmin Ride")
                    .font(.headline)
                    // Removed opacity logic here so rows always appear active
                
                Spacer()
                
                // Only show bolt if we actually have the data in the summary
                if let avgPower = activity.averagePowerInWatts, avgPower > 0 {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }
            
            HStack(spacing: 16) {
                Label(formatDuration(activity.durationInSeconds), systemImage: "clock")
                    .font(.caption)
                
                if let distance = activity.distanceInMeters {
                    Label(
                        weatherViewModel.settings.units == .metric ?
                            formatDistance(distance) :
                            formatDistanceMiles(distance),
                        systemImage: "figure.outdoor.cycle"
                    )
                    .font(.caption)
                }
                
                if let avgPower = activity.averagePowerInWatts, avgPower > 0 {
                    Label("\(Int(avgPower))W", systemImage: "bolt")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .foregroundColor(.secondary)
            // Removed opacity logic here
            
            Text(activity.startDate.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
                // Removed opacity logic here
        }
        .padding(.vertical, 4)
    }
    
    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000
        return String(format: "%.2f km", km)
    }
    
    private func formatDistanceMiles(_ meters: Double) -> String {
        let miles = meters * 0.000621371
        return String(format: "%.2f mi", miles)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Data Models for Ride Analysis Import

struct ImportedRideData {
    let activityName: String
    let startTime: Date
    let duration: TimeInterval
    let distance: Double
    let gpsPoints: [GPSPoint]
    let powerData: [PowerDataPoint]
    let heartRateData: [HeartRateDataPoint]
    let averagePower: Double?
    let normalizedPower: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let elevationGain: Double?
    let elevationLoss: Double?
    let calories: Double?
}

struct GPSPoint {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let elevation: Double?
    let speed: Double?
    let distance: Double?
}

struct PowerDataPoint {
    let timestamp: Date
    let watts: Double
}

struct HeartRateDataPoint {
    let timestamp: Date
    let bpm: Int
}
