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
                        Text("Your recent Wahoo rides will appear here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(viewModel.activities) { activity in
                            WahooActivityRow(activity: activity)
                                .environmentObject(weatherViewModel)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectActivity(activity)
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
            .sheet(isPresented: $viewModel.showingAnalysisImport) {
                if let activity = viewModel.selectedActivity {
                    WahooImportSheet(
                        activity: activity,
                        viewModel: viewModel,
                        wahooService: wahooService,
                        weatherViewModel: weatherViewModel
                    )
                }
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
    @EnvironmentObject var weatherViewModel: WeatherViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(activity.name)
                .font(.headline)
            
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
                
                if activity.work > 0 {
                    Label("\(Int(activity.work)) kJ", systemImage: "bolt")
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
struct WahooImportSheet: View {
    let activity: WahooWorkoutSummary
    @ObservedObject var viewModel: WahooActivitiesViewModel
    @ObservedObject var wahooService: WahooService
    @ObservedObject var weatherViewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if viewModel.isImporting {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Importing from Wahoo...")
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
                            
                            if activity.work > 0 {
                                InfoRow(label: "Work", value: "\(Int(activity.work)) kJ")
                            } else {
                                InfoRow(label: "Work", value: "N/A")
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