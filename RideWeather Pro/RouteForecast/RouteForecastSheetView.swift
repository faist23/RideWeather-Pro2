//
//  RouteForecastSheetView.swift
//  RideWeather Pro
//
//  This view lives inside the bottom sheet on the Plan tab
//  and manages the workflow from Import -> Controls -> Analysis.
//

import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct RouteForecastSheetView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var stravaService: StravaService
    @EnvironmentObject var wahooService: WahooService

    @Binding var isImporting: Bool
    @Binding var importedFileName: String
    @Binding var selectedDetent: PresentationDetent

    @State private var showingDatePicker = false
    @State private var showingTimePicker = false
    @State private var showingSettings = false
    
    // For import button animation
    @State private var importButtonPressed = false

    // To pass to the fileImporter
    let supportedTypes: [UTType] = [
        UTType(filenameExtension: "gpx")!,
        UTType(filenameExtension: "fit")!,
    ]
    
    var body: some View {
        // We use a NavigationStack for the "Settings" button
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    
                    // --- 1. IMPORT SECTION ---
                    // This is always visible at the top
                    importSection
                    
                    // --- 2. CONTROLS SECTION ---
                    // This appears only after a route is loaded
                    if viewModel.routePoints.count > 0 {
                        rideTimeSection
                        
                        generateButton
                    }
                    
                    // --- 3. ANALYSIS SECTION ---
                    // This appears after a forecast is generated
                    if !viewModel.weatherDataForRoute.isEmpty {
                        Divider()
                            .padding(.vertical, 10)
                        
                        // We embed the dashboard directly here.
                        // It's already in its own file: OptimizedUIComponents.swift
                        OptimizedUnifiedRouteAnalyticsDashboard()
                            .environmentObject(viewModel)
                    }
                    
                    // Show a spinner if the view model is loading
                    if viewModel.isLoading {
                        ProgressView("Loading Forecast...")
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .background(.clear) // Let the sheet's material show
            .navigationTitle("Plan Forecast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: supportedTypes) { result in
                switch result {
                case .success(let url):
                    let fileName = url.lastPathComponent
                    // We use the viewModel's property to clean the name
                    viewModel.lastImportedFileName = fileName
                    importedFileName = viewModel.routeDisplayName // Use the cleaned name
                    
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    
                    viewModel.importRoute(from: url)
                    
                case .failure(let error):
                    print("File import failed: \(error.localizedDescription)")
                    let notificationFeedback = UINotificationFeedbackGenerator()
                    notificationFeedback.notificationOccurred(.error)
                }
            }
            .sheet(isPresented: $showingDatePicker) { datePickerSheet }
            .sheet(isPresented: $showingTimePicker) { timePickerSheet }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(viewModel)
            }
        }
    }
    
    // MARK: - View Components
    
    // This is the content from your old ModernRouteBottomControlsView
    private var importSection: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    importButtonPressed = true
                }
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
            .disabled(viewModel.isLoading)
        }
    }
    
    @ViewBuilder
    private var importButtonLabel: some View {
        if case .parsing = viewModel.uiState {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(.white.opacity(0.9))
                Text("Importing Route...")
            }
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
        } else {
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
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var generateButton: some View {
        Button {
            // Expand to full sheet to show analysis
            withAnimation(.smooth) {
                selectedDetent = .large // .large is built-in
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
        .disabled(viewModel.routePoints.isEmpty || viewModel.isLoading)
    }

    // MARK: - Date/Time Pickers (Copied from ModernRouteBottomControlsView)
    
    private var datePickerSheet: some View {
        NavigationStack {
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
        NavigationStack {
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
    
    // MARK: - Computed Properties (Copied)
    
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
        if !viewModel.routePoints.isEmpty {
            return viewModel.routeDisplayName // Use the cleaned name
        } else {
            return "Import Route"
        }
    }
    
    private func getImportButtonColor() -> Color {
        return !viewModel.routePoints.isEmpty ? .green : .blue
    }
    
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
