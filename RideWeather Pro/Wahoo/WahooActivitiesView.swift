//
//  WahooActivitiesView.swift
//  RideWeather Pro
//

import SwiftUI

struct WahooActivitiesView: View {
    @EnvironmentObject var wahooService: WahooService
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    @StateObject private var viewModel = WahooActivitiesViewModel()
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
                            viewModel.loadActivities(service: wahooService)
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
                        Text("Your recent Wahoo biking rides will appear here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(viewModel.activities) { activity in
                            WahooActivityRow(activity: activity)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectActivity(activity, service: wahooService)
                                }
                        }
                    }
                    .refreshable {
                        viewModel.loadActivities(service: wahooService)
                    }
                }
            }
            .navigationTitle("Wahoo Activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingAnalysisImport, onDismiss: {
                viewModel.clearSelection() // Clear detail view when sheet closes
            }) {
                WahooImportSheet(
                    viewModel: viewModel,
                    wahooService: wahooService,
                    weatherViewModel: weatherViewModel
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewAnalysisImported"))) { _ in
                dismiss()
            }
        }
        .onAppear {
            if viewModel.activities.isEmpty {
                viewModel.loadActivities(service: wahooService)
            }
        }
    }
}

struct WahooActivityRow: View {
    let activity: WahooWorkoutSummary
    var body: some View {
        VStack(alignment: .leading) {
            Text(activity.displayName)
                .font(.headline)
            if let date = activity.rideDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No Date")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}



// MARK: - Import Sheet
struct WahooImportSheet: View {
    @ObservedObject var viewModel: WahooActivitiesViewModel
    @ObservedObject var wahooService: WahooService
    @ObservedObject var weatherViewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if viewModel.isFetchingDetail || viewModel.isImporting {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text(viewModel.isImporting ? "Importing from Wahoo..." : "Fetching Ride Details...")
                            .font(.headline)
                        Text(viewModel.isImporting ? "Fetching activity streams and analyzing performance" : "Loading ride stats...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                
                } else if let activity = viewModel.selectedActivityDetail {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(activity.name ?? "Wahoo Ride")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            WahooInfoRow(  // <-- RENAMED
                                label: "Distance",
                                value: weatherViewModel.settings.units == .metric ?
                                    String(format: "%.1f km", activity.distanceKm) :
                                    String(format: "%.1f mi", activity.distanceMiles)
                            )
                            WahooInfoRow(label: "Duration", value: activity.durationFormatted) // <-- RENAMED
                            
                            if activity.work > 0 {
                                let work = activity.work
                                WahooInfoRow(label: "Work", value: "\(Int(work)) kJ") // <-- RENAMED
                            } else {
                                WahooInfoRow(label: "Work", value: "N/A") // <-- RENAMED
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
                            viewModel.importActivity(service: wahooService, weatherViewModel: weatherViewModel)
                        }) {
                            HStack {
                                Image(systemName: "chart.xyaxis.line")
                                Text("Analyze This Ride")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("Error Loading Details")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .navigationTitle("Import from Wahoo")
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



// Renamed struct `InfoRow` to `WahooInfoRow` as you requested.
struct WahooInfoRow: View {
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

