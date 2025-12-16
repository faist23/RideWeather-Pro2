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
        
        print("📥 GarminActivityImportView: Starting to load activities...")
        
        do {
            activities = try await garminService.fetchRecentActivities(limit: 50)
            print("✅ GarminActivityImportView: Successfully loaded \(activities.count) activities")
            if activities.isEmpty {
                errorMessage = nil // Show empty state instead of error
                print("ℹ️ GarminActivityImportView: No cycling activities found")
            }
        } catch {
            let errorMsg = error.localizedDescription
            errorMessage = errorMsg
            print("❌ GarminActivityImportView: Failed to load activities")
            print("   Error: \(errorMsg)")
            if let garminError = error as? GarminService.GarminError {
                print("   Garmin Error Type: \(garminError)")
            }
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
                
                // Send notification with Garmin source
                if let currentAnalysis = rideViewModel.currentAnalysis {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NewAnalysisImported"),
                        object: currentAnalysis,
                        userInfo: ["source": "garmin"]
                    )
                }
                
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
        
        print("🔄 Converting Garmin activity to ride data...")
        print("   Activity: \(activity.activityName ?? "Unnamed")")
        print("   Samples: \(activity.samples?.count ?? 0)")
        
        if let samples = activity.samples {
            var cumulativeDistance: Double = 0
            var previousLocation: (lat: Double, lon: Double)? = nil
            
            for (index, sample) in samples.enumerated() {
                let timestamp = Date(timeIntervalSince1970: TimeInterval(sample.startTimeInSeconds))
                
                // Calculate distance from previous point
                if let lat = sample.latitude, let lon = sample.longitude {
                    if let prevLoc = previousLocation {
                        let loc1 = CLLocation(latitude: prevLoc.lat, longitude: prevLoc.lon)
                        let loc2 = CLLocation(latitude: lat, longitude: lon)
                        let segmentDistance = loc1.distance(from: loc2)
                        cumulativeDistance += segmentDistance
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
                
                // Power data - INCLUDE ALL SAMPLES
                // If power is nil, treat it as 0 (coasting/no power meter for that second)
                let powerValue = sample.power ?? 0.0
                powerData.append(PowerDataPoint(
                    timestamp: timestamp,
                    watts: powerValue
                ))
                
                // Heart rate data
                if let hr = sample.heartRate, hr > 0 {
                    heartRateData.append(HeartRateDataPoint(
                        timestamp: timestamp,
                        bpm: hr
                    ))
                }
                
                // Log first few samples for debugging
                if index < 3 {
                    print("   Sample \(index): lat=\(sample.latitude?.description ?? "nil"), lon=\(sample.longitude?.description ?? "nil"), power=\(powerValue), hr=\(sample.heartRate?.description ?? "nil")")
                }
            }
            
            print("   📏 Total calculated distance: \(String(format: "%.2f", cumulativeDistance / 1000))km")
        }
        
        let powerAboveZero = powerData.filter { $0.watts > 0 }.count
        
        print("   ✅ Converted:")
        print("      - GPS points: \(gpsPoints.count)")
        print("      - Power samples: \(powerData.count) (\(powerAboveZero) > 0W)")
        print("      - Heart rate samples: \(heartRateData.count)")
        
        if gpsPoints.isEmpty {
            print("   ⚠️ WARNING: No GPS points found!")
        }
        if powerData.isEmpty {
            print("   ⚠️ WARNING: No power data found!")
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
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                // Ride name and power indicator
                HStack {
                    Text(activity.activityName ?? "Garmin Ride")
                        .font(.headline)
                    
                    Spacer()
                    
                    // Power meter indicator
                    if let avgPower = activity.averagePowerInWatts, avgPower > 0 {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                
                // Duration, distance, and avg power
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
                
                // Ride start date/time
                Text(formatDate(activity.startDate))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                onImport()
            } label: {
                Text("Import")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
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
