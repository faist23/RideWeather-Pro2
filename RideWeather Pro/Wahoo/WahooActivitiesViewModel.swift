//
//  WahooActivitiesViewModel.swift
//  RideWeather Pro
//

import SwiftUI
import Combine

@MainActor
class WahooActivitiesViewModel: ObservableObject {
    @Published var activities: [WahooWorkoutSummary] = []
    @Published var selectedActivity: WahooWorkoutSummary?
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var errorMessage: String?
    @Published var showingAnalysisImport = false
    
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
    
    func selectActivity(_ activity: WahooWorkoutSummary) {
        selectedActivity = activity
        showingAnalysisImport = true
    }
    
    func importActivity(service: WahooService, weatherViewModel: WeatherViewModel) {
        guard let activity = selectedActivity else { return }
        
        isImporting = true
        errorMessage = nil
        
        Task {
            do {
                print("WahooImport: Starting import for activity \(activity.id)")
                
                // 1. Fetch detailed stream data
                let streams = try await service.fetchWorkoutData(workoutId: activity.id)
                print("WahooImport: Streams fetched successfully")

                // 2. Convert Wahoo streams to app's standard FITDataPoint format
                let dataPoints = service.convertWahooDataToFITDataPoints(workout: activity, streams: streams)
                guard !dataPoints.isEmpty else {
                    throw WahooService.WahooError.invalidResponse
                }
                print("WahooImport: Converted \(dataPoints.count) data points")

                // 3. Analyze data points using the *existing* RideFileAnalyzer
                let analyzer = RideFileAnalyzer(settings: weatherViewModel.settings)
                
                // Use metadata for moving/elapsed time
                let elapsedTime = (activity.endDate ?? Date()).timeIntervalSince(activity.startDate ?? Date())
                let movingTime = activity.time
                
                var analysis = analyzer.analyzeRide(
                    dataPoints: dataPoints,
                    ftp: Double(weatherViewModel.settings.functionalThresholdPower),
                    weight: weatherViewModel.settings.bodyWeight,
                    plannedRide: nil,
                    isPreFiltered: true,
                    elapsedTimeOverride: elapsedTime,
                    movingTimeOverride: movingTime
                )
                
                // 4. Update the ride name to match Wahoo
                analysis = RideAnalysis(
                    id: analysis.id, date: analysis.date, rideName: activity.name,
                    duration: analysis.duration, distance: analysis.distance, metadata: analysis.metadata,
                    averagePower: analysis.averagePower, normalizedPower: analysis.normalizedPower,
                    intensityFactor: analysis.intensityFactor, trainingStressScore: analysis.trainingStressScore,
                    variabilityIndex: analysis.variabilityIndex, peakPower5s: analysis.peakPower5s,
                    peakPower1min: analysis.peakPower1min, peakPower5min: analysis.peakPower5min,
                    peakPower20min: analysis.peakPower20min, terrainSegments: analysis.terrainSegments,
                    powerAllocation: analysis.powerAllocation, consistencyScore: analysis.consistencyScore,
                    pacingRating: analysis.pacingRating, powerVariability: analysis.powerVariability,
                    fatigueDetected: analysis.fatigueDetected, fatigueOnsetTime: analysis.fatigueOnsetTime,
                    powerDeclineRate: analysis.powerDeclineRate, plannedRideId: analysis.plannedRideId,
                    segmentComparisons: analysis.segmentComparisons, overallDeviation: analysis.overallDeviation,
                    surgeCount: analysis.surgeCount, pacingErrors: analysis.pacingErrors,
                    performanceScore: analysis.performanceScore, insights: analysis.insights,
                    powerZoneDistribution: analysis.powerZoneDistribution
                )
                
                print("WahooImport: Analysis complete - Score: \(analysis.performanceScore)")
                
                // 5. Save analysis
                let storage = AnalysisStorageManager()
                storage.saveAnalysis(analysis)
                print("WahooImport: Analysis saved")
                
                await MainActor.run {
                    self.isImporting = false
                    self.showingAnalysisImport = false
                    
                    // 6. Post notification to update RideAnalysisView and dismiss sheets
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NewAnalysisImported"),
                            object: analysis
                        )
                        print("WahooImport: Notification posted")
                    }
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