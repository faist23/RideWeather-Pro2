//
//  GarminActivityImportView.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 12/8/25.
//


import SwiftUI

struct GarminActivityImportView: View {
    @EnvironmentObject var garminService: GarminService
    @EnvironmentObject var rideViewModel: RideAnalysisViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var activities: [GarminActivitySummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    
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
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading your Garmin activities...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.orange)
                        Text("Unable to load activities")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Retry") {
                            Task { await loadActivities() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if activities.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "figure.outdoor.cycle")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue)
                        Text("No Activities Found")
                            .font(.headline)
                        Text("Complete cycling activities in Garmin Connect to import them here")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List {
                        ForEach(filteredActivities) { activity in
                            GarminActivityRow(activity: activity) {
                                Task {
                                    await importActivity(activity)
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search activities")
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Import from Garmin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await loadActivities()
            }
        }
    }
    
    private func loadActivities() async {
        isLoading = true
        errorMessage = nil
        
        do {
            activities = try await garminService.fetchRecentActivities(limit: 50)
            if activities.isEmpty {
                errorMessage = nil // Show empty state instead of error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func importActivity(_ activity: GarminActivitySummary) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Fetch full activity details with GPS samples
            let activityDetail = try await garminService.fetchActivityDetails(activityId: activity.activityId)
            
            // Convert to your app's format
            let rideData = convertToRideData(activityDetail)
            
            await MainActor.run {
                // Import into ride analysis
                rideViewModel.importRideData(rideData)
                dismiss()
            }
        } catch {
            errorMessage = "Failed to import activity: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func convertToRideData(_ activity: GarminActivityDetail) -> ImportedRideData {
        var gpsPoints: [GPSPoint] = []
        var powerData: [PowerDataPoint] = []
        var heartRateData: [HeartRateDataPoint] = []
        
        if let samples = activity.samples {
            for sample in samples {
                let timestamp = Date(timeIntervalSince1970: TimeInterval(sample.startTimeInSeconds))
                
                // GPS points
                if let lat = sample.latitude, let lon = sample.longitude {
                    gpsPoints.append(GPSPoint(
                        timestamp: timestamp,
                        latitude: lat,
                        longitude: lon,
                        elevation: sample.elevation,
                        speed: sample.speed,
                        distance: nil 
                    ))
                }
                
                // Power data
                if let power = sample.power {
                    powerData.append(PowerDataPoint(
                        timestamp: timestamp,
                        watts: power
                    ))
                }
                
                // Heart rate data
                if let hr = sample.heartRate {
                    heartRateData.append(HeartRateDataPoint(
                        timestamp: timestamp,
                        bpm: hr
                    ))
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
    let onImport: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.activityName ?? "Ride")
                    .font(.headline)
                
                Text(formatDate(activity.startDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 16) {
                    if let distance = activity.distanceInMeters {
                        Label(formatDistance(distance), systemImage: "arrow.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Label(formatDuration(activity.durationInSeconds), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let avgPower = activity.averagePowerInWatts {
                        Label("\(Int(avgPower))W", systemImage: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Button {
                onImport()
            } label: {
                Text("Import")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000
        return String(format: "%.1f km", km)
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
