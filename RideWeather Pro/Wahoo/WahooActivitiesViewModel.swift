//
//  WahooActivitiesViewModel.swift
//  RideWeather Pro
//

import SwiftUI
import Combine
import FitFileParser

@MainActor
class WahooActivitiesViewModel: ObservableObject {
    @Published var activities: [WahooWorkoutSummary] = []
    @Published var selectedActivityDetail: WahooWorkoutSummary? // <-- This holds the detail
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var isFetchingDetail = false // <-- NEW: For the sheet's spinner
    @Published var errorMessage: String?
    @Published var showingAnalysisImport = false
    @Published var analysis: RideAnalysis?
    @Published var analysisSources: [UUID: RideSourceInfo] = [:]
    
    @Published var isLoadingMore = false
    @Published var hasMorePages = true
    private var currentPage = 1
    private let perPage = 50

    private let settings: AppSettings  

    nonisolated init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    func loadActivities(service: WahooService) {
        isLoading = true
        errorMessage = nil
        
        currentPage = 1
        activities = []

        Task {
            do {
                let response = try await service.fetchRecentWorkouts(page: self.currentPage, perPage: perPage) // <-- Fetch page 0
                let workouts = response.workouts
                
                let filteredWorkouts = workouts.filter {
                    let distance = Double($0.workoutSummary?.distanceAccum ?? "0") ?? 0
                    let power = Double($0.workoutSummary?.powerAvg ?? "0") ?? 0 // Get average power
                    return distance > 0 && power > 0 // Must have distance AND power
                }

                await MainActor.run {
                    self.activities = filteredWorkouts
                    self.isLoading = false
                    // --- REVISED PAGINATION LOGIC ---
                    if let total = response.total, let p = response.page, let pp = response.perPage, total > 0, pp > 0 {
                        self.hasMorePages = (p + 1) * pp < total
                    } else {
                        // Fallback if pagination data is missing
                        self.hasMorePages = workouts.count == self.perPage
                    }
                    self.currentPage = 2 // <-- Next page is 1
                    // --- END REVISED LOGIC ---
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    func loadMoreActivities(service: WahooService) {
        guard !isLoadingMore && hasMorePages else { return }
        
        isLoadingMore = true
        errorMessage = nil
        
        Task {
            do {
                let response = try await service.fetchRecentWorkouts(page: self.currentPage, perPage: self.perPage)
                let newWorkouts = response.workouts
                
                // --- MODIFIED FILTER ---
                let filteredWorkouts = newWorkouts.filter {
                    let distance = Double($0.workoutSummary?.distanceAccum ?? "0") ?? 0
                    let power = Double($0.workoutSummary?.powerAvg ?? "0") ?? 0 // Get average power
                    return distance > 0 && power > 0 // Must have distance AND power
                }
                
                await MainActor.run {
                    self.activities.append(contentsOf: filteredWorkouts) // <-- Use filtered list
                    // --- REVISED PAGINATION LOGIC ---
                    if let total = response.total, let p = response.page, let pp = response.perPage, total > 0, pp > 0 {
                        self.hasMorePages = (p + 1) * pp < total
                    } else {
                        // Fallback if pagination data is missing
                        self.hasMorePages = newWorkouts.count == self.perPage
                    }
                    self.isLoadingMore = false
                    self.currentPage += 1
                    // --- END REVISED LOGIC ---
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoadingMore = false
                }
            }
        }
    }
    
    // --- FIX: This function now fetches the detail when a row is tapped ---
    func selectActivity(_ activitySummary: WahooWorkoutSummary, service: WahooService) {
        Task {
            isFetchingDetail = true
            showingAnalysisImport = true // Show the sheet immediately
            errorMessage = nil
            
            do {
                // Make the second API call for details
                let detail = try await service.fetchWorkoutDetail(id: activitySummary.id)
                self.selectedActivityDetail = detail
                self.isFetchingDetail = false
            } catch {
                self.errorMessage = "Could not load ride details: \(error.localizedDescription)"
                self.isFetchingDetail = false
            }
        }
    }
    
    // --- NEW: Helper to clear state when sheet is dismissed ---
    func clearSelection() {
        selectedActivityDetail = nil
        showingAnalysisImport = false
        errorMessage = nil
    }

    func importActivity(service: WahooService, weatherViewModel: WeatherViewModel) {
        guard let activity = selectedActivityDetail else { return }

        isImporting = true
        errorMessage = nil

        if let fitFileUrlString = activity.workoutSummary?.file?.url {
            print("Analyze ride URL:", fitFileUrlString)
        } else {
            print("No FIT file available for this ride")
        }

        Task {
            do {
                print("WahooImport: Starting import for activity \(activity.id)")

                guard let fitFileUrlString = activity.workoutSummary?.file?.url,
                      let fitFileUrl = URL(string: fitFileUrlString) else {
                    print("No FIT file available for this ride (\(activity.id))")
                    await MainActor.run {
                        self.errorMessage = "No downloadable ride file found for this activity."
                        self.isImporting = false
                    }
                    return
                }

                let (fileData, response) = try await URLSession.shared.data(from: fitFileUrl)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    print("Failed to download FIT file. HTTP \(httpResponse.statusCode)")
                    await MainActor.run {
                        self.errorMessage = "Failed to download ride file from Wahoo (\(httpResponse.statusCode))."
                        self.isImporting = false
                    }
                    return
                }

                do {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("tempImportedRide.fit")
                    try fileData.write(to: tempURL)
                    let parser = FITFileParser()
                    let fitDataPoints = try await parser.parseFile(at: tempURL)
                    print("WahooImport: Parsed \(fitDataPoints.count) FIT data points.")
                    
                    let analyzer = RideFileAnalyzer(settings: self.settings)
                    let rideName = activity.workoutSummary?.name ?? activity.name ?? "Wahoo Ride"
                    
                    // --- START FIX ---
                    
                    // 1. Get all THREE return values from the function
                    let (powerGraphData, hrGraphData, elevationGraphData) = analyzer.generateGraphData(dataPoints: fitDataPoints)
                    
                    let heartRates = fitDataPoints.compactMap { $0.heartRate }
                    let averageHeartRate = heartRates.isEmpty ? nil : (Double(heartRates.reduce(0, +)) / Double(heartRates.count))
                    
                    // 2. Pass ALL graph data into the analyzeRide function
                    var rideAnalysis = analyzer.analyzeRide(
                        dataPoints: fitDataPoints,
                        ftp: Double(settings.functionalThresholdPower),
                        weight: settings.bodyWeight,
                        plannedRide: nil,
                        averageHeartRate: averageHeartRate,
                        powerGraphData: powerGraphData,
                        heartRateGraphData: hrGraphData,
                        elevationGraphData: elevationGraphData // <-- Pass it here
                    )
                    // --- END FIX ---
                    
                    rideAnalysis.rideName = rideName // <-- Set correct name on the mutable copy
                    self.analysis = rideAnalysis
                    print("WahooImport: Analysis complete - Score: \(rideAnalysis.performanceScore)")

                    // Save analysis
                    let storage = AnalysisStorageManager()
                    storage.saveAnalysis(rideAnalysis)
                    print("WahooImport: Analysis saved")

                    let sourceInfo = RideSourceInfo(type: .wahoo, fileName: nil) 
                    self.analysisSources[rideAnalysis.id] = sourceInfo
                    storage.saveSource(sourceInfo, for: rideAnalysis.id)

                    await MainActor.run {
                        // ✅ NEW: Clear the previous pacing plan when importing new route
                         weatherViewModel.clearAdvancedPlan()
                         
                        self.isImporting = false
                        self.showingAnalysisImport = false

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("NewAnalysisImported"),
                                object: rideAnalysis
                            )
                            print("WahooImport: Notification posted")
                        }
                    }

                } catch {
                    print("FIT Parse/Analysis error:", error)
                    await MainActor.run {
                        self.errorMessage = "Failed to import or analyze FIT file: \(error.localizedDescription)"
                        self.isImporting = false
                    }
                    return
                }

            } catch {
                print("WahooImport Error: \(error)")
                await MainActor.run {
                    self.errorMessage = "Import failed: \(error.localizedDescription)"
                    self.isImporting = false
                }
            }
        }
    }
}
