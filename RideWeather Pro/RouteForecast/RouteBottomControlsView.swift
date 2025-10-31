//
// RouteBottomControlsView.swift
//

import SwiftUI
import CoreLocation

struct ModernRouteBottomControlsView: View {
    @State private var showingStravaImport = false
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var stravaService: StravaService  // ✅ ADD THIS
    @Binding var isImporting: Bool
    @Binding var showBottomControls: Bool
    @Binding var importedFileName: String
    
    @State private var showingDatePicker = false
    @State private var showingTimePicker = false
    @State private var showingSettings = false
    
    // Import button animation
    @State private var importButtonPressed = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Quick action buttons
            HStack(spacing: 12) {
                Button {
                    // Visual feedback for button press
                    withAnimation(.easeInOut(duration: 0.15)) {
                        importButtonPressed = true
                    }
                    
                    // Reset animation and trigger file picker
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            importButtonPressed = false
                        }
                        isImporting = true
                    }
                } label: {
                    importButtonLabel
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .scaleEffect(importButtonPressed ? 0.95 : 1.0)
                .tint(getImportButtonColor())
                .disabled(viewModel.isLoading) // ✅ ADDED: Disable the button while parsing

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                }
                .buttonStyle(.bordered)
                .frame(width: 56, height: 56)
                .disabled(viewModel.isLoading) // ✅ ADDED: Also disable settings while parsing
 
                if stravaService.isAuthenticated {
                    Button {
                        showingStravaImport = true
                    } label: {
                        HStack(spacing: 8) {
                            Image("strava_logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 16)
                            Text("Import")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.orange)
                    .disabled(viewModel.isLoading)
                }

            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            
            // Smart input sections
            VStack(spacing: 16) {
                // Ride Time Section
                rideTimeSection
                
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            
            // Generate Button
            generateButton
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 20, y: -5)
        .sheet(isPresented: $showingDatePicker) {
            datePickerSheet
        }
        .sheet(isPresented: $showingTimePicker) {
            timePickerSheet
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showingStravaImport) {
            StravaRouteImportView()
                .environmentObject(viewModel)
                .environmentObject(stravaService)
        }

    }
    
    // MARK: - Import Button Label
    
    // ✅ ADDED: This new ViewBuilder creates the correct button label based on the current UI state.
    @ViewBuilder
    private var importButtonLabel: some View {
        // When the state is .parsing, show a progress indicator.
        if case .parsing = viewModel.uiState {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(.white.opacity(0.9))
                Text("Importing Route...")
            }
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
        } else {
            // Otherwise, show the normal button content.
            HStack(spacing: 8) {
                Image(systemName: getImportIcon())
                    .symbolEffect(.bounce, value: importButtonPressed)
                    .symbolRenderingMode(.hierarchical)
                
                Text(getImportButtonText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Import Button Logic
    
    private func getImportIcon() -> String {
        if !viewModel.routePoints.isEmpty {
            return "checkmark.circle.fill"
        } else if importButtonPressed {
            return "arrow.down.circle.fill"
        } else {
            return "square.and.arrow.down"
        }
    }
    
    private func getImportButtonText() -> String {
        if !viewModel.routePoints.isEmpty && !importedFileName.isEmpty {
            return importedFileName
        } else if !viewModel.routePoints.isEmpty {
            return "Route Loaded"
        } else {
            return "Import Route"
        }
    }
    
    private func getImportButtonColor() -> Color {
        return !viewModel.routePoints.isEmpty ? .green : .blue
    }
    
    // MARK: - View Components
    
    private var rideTimeSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "clock.fill")
                    .foregroundColor(.secondary)
                    .font(.title3)
                
                Text("Ride Time")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            HStack(spacing: 12) {
                // Date Button
                Button {
                    showingDatePicker = true
                } label: {
                    Text(formattedDate)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                }
                
                // Time Button
                Button {
                    showingTimePicker = true
                } label: {
                    Text(formattedTime)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    
    private var generateButton: some View {
        Button {
            withAnimation(.smooth) {
                showBottomControls = false
            }
            
            Task {
                await viewModel.calculateAndFetchWeather()
            }
        } label: {
            HStack {
                Image(systemName: "play.fill")
                    .font(.title3)
                Text("Generate Weather Forecast")
                    .font(.headline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(viewModel.routePoints.isEmpty)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
    
    private var datePickerSheet: some View {
        NavigationView {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: $viewModel.rideDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                
                Spacer()
            }
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingDatePicker = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private var timePickerSheet: some View {
        NavigationView {
            VStack {
                DatePicker(
                    "Select Time",
                    selection: $viewModel.rideDate,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .padding()
                
                Spacer()
            }
            .navigationTitle("Select Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingTimePicker = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, MMM d"
        return formatter.string(from: viewModel.rideDate)
    }
    
     var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: viewModel.rideDate)
    }
}
