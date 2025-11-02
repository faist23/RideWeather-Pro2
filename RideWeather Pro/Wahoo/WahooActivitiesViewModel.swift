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

    private let settings: AppSettings  // 🔥 ADD THIS

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    func loadActivities(service: WahooService) {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let workouts = try await service.fetchRecentWorkouts()
                await MainActor.run {
                    self.activities = workouts
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
                    let rideAnalysis = analyzer.analyzeRide(
                        dataPoints: fitDataPoints,
                        ftp: Double(settings.functionalThresholdPower),
                        weight: settings.bodyWeight,
                        plannedRide: nil
                    )
                    // Assign to published property for UI
                    self.analysis = rideAnalysis
                    print("WahooImport: Analysis complete - Score: \(rideAnalysis.performanceScore)")

                    // Save analysis
                    let storage = AnalysisStorageManager()
                    storage.saveAnalysis(rideAnalysis)
                    print("WahooImport: Analysis saved")

                    await MainActor.run {
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
