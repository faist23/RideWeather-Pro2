//
//  AdvancedPacingView.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 9/17/25.
//


//
//  MissingViews.swift
//  RideWeather Pro - Contains all the missing view files
//

import SwiftUI

// MARK: - AdvancedPacingView.swift

struct AdvancedPacingView: View {
    @ObservedObject var controller: AdvancedCyclingController
    @State private var selectedStrategy: PacingStrategy = .balanced
    @State private var showingExport = false
    @State private var exportText = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // Strategy Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pacing Strategy")
                        .font(.headline)
                    
                    ForEach(PacingStrategy.allCases, id: \.self) { strategy in
                        Button(action: {
                            selectedStrategy = strategy
                        }) {
                            HStack {
                                Image(systemName: selectedStrategy == strategy ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedStrategy == strategy ? .blue : .gray)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(strategy.description)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.primary)
                                    
                                    Text(strategyDescription(for: strategy))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(12)
                            .background(selectedStrategy == strategy ? Color.blue.opacity(0.1) : Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                if let pacing = controller.pacingPlan {
                    PacingPlanDisplay(pacing: pacing)
                } else if controller.isGeneratingPlan {
                    ProgressView("Generating pacing plan...")
                        .frame(maxWidth: .infinity, maxHeight: 100)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "bolt.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text("No pacing plan generated yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Generate a power analysis first from the main route dashboard")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                }
                
                if controller.pacingPlan != nil {
                    Button("Export CSV") {
                        exportText = controller.exportRacePlanCSV()
                        showingExport = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle("Smart Pacing")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingExport) {
            ShareSheet(activityItems: [exportText])
        }
    }
    
    private func strategyDescription(for strategy: PacingStrategy) -> String {
        switch strategy {
        case .balanced:
            return "Well-rounded approach balancing speed and sustainability"
        case .conservative:
            return "Start easier, maintain energy for later in the ride"
        case .aggressive:
            return "Go hard early, accept some fade later"
        case .negativeSplit:
            return "Build power progressively throughout the ride"
        case .evenEffort:
            return "Adjust for terrain to maintain constant physiological stress"
        }
    }
}

// MARK: - FuelingStrategyView.swift

struct FuelingStrategyView: View {
    @ObservedObject var controller: AdvancedCyclingController
    @State private var showingExport = false
    @State private var exportText = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let fueling = controller.fuelingStrategy {
                    FuelingPlanDisplay(fueling: fueling)
                    
                    // Export buttons
                    HStack(spacing: 16) {
                        Button("Export Schedule") {
                            exportText = fueling.exportScheduleAsCSV()
                            showingExport = true
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Print Plan") {
                            exportText = fueling.generatePrintablePlan()
                            showingExport = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                } else if controller.isGeneratingPlan {
                    ProgressView("Generating fueling strategy...")
                        .frame(maxWidth: .infinity, maxHeight: 100)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "drop.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text("No fueling strategy available")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Generate a race plan first to see personalized nutrition guidance")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                }
            }
            .padding()
        }
        .navigationTitle("Fueling Strategy")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingExport) {
            ShareSheet(activityItems: [exportText])
        }
    }
}

// MARK: - DeviceSyncView.swift

struct DeviceSyncView: View {
    @ObservedObject var controller: AdvancedCyclingController
    @StateObject private var deviceSync = DeviceSyncManager()
    @State private var selectedPlatforms: Set<DevicePlatform> = []
    @State private var showingOptions = false
    @State private var workoutOptions = WorkoutOptions()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // Platform Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Devices")
                        .font(.headline)
                    
                    ForEach(DevicePlatform.allCases, id: \.self) { platform in
                        Button(action: {
                            if selectedPlatforms.contains(platform) {
                                selectedPlatforms.remove(platform)
                            } else {
                                selectedPlatforms.insert(platform)
                            }
                        }) {
                            HStack {
                                Image(systemName: selectedPlatforms.contains(platform) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(selectedPlatforms.contains(platform) ? .blue : .gray)
                                
                                Text(platform.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                // Show sync status if available
                                if let status = deviceSync.syncStatus[platform] {
                                    syncStatusBadge(for: status)
                                }
                            }
                            .padding(12)
                            .background(selectedPlatforms.contains(platform) ? Color.blue.opacity(0.1) : Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Sync Options
                if !selectedPlatforms.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Workout Options")
                            .font(.headline)
                        
                        VStack(spacing: 8) {
                            Toggle("Include Warmup", isOn: .constant(workoutOptions.includeWarmup))
                                .disabled(true) // Just for display
                            Toggle("Include Cooldown", isOn: .constant(workoutOptions.includeCooldown))
                                .disabled(true) // Just for display
                            
                            HStack {
                                Text("Power Tolerance")
                                Spacer()
                                Text("\(Int(workoutOptions.powerTolerance))%")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        
                        Button("Customize Options") {
                            showingOptions = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // Sync Button
                if !selectedPlatforms.isEmpty && controller.pacingPlan != nil {
                    Button("Sync to Selected Devices") {
                        Task {
                            await controller.syncToDevices(Array(selectedPlatforms), options: workoutOptions)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.headline)
                }
                
                // Sync Results
                if !controller.syncResults.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sync Results")
                            .font(.headline)
                        
                        ForEach(controller.syncResults, id: \.platform) { result in
                            SyncResultCard(result: result)
                        }
                    }
                }
                
                // Status when no plan available
                if controller.pacingPlan == nil {
                    VStack(spacing: 16) {
                        Image(systemName: "externaldrive.badge.xmark")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text("No workout to sync")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Generate a pacing plan first to sync workouts to your devices")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                }
            }
            .padding()
        }
        .navigationTitle("Device Sync")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingOptions) {
            WorkoutOptionsSheet(
                options: $workoutOptions,
                selectedPlatforms: selectedPlatforms
            ) {
                showingOptions = false
            }
        }
    }
    
    @ViewBuilder
    private func syncStatusBadge(for status: DeviceSyncManager.SyncStatus) -> some View {
        switch status {
        case .idle:
            Text("Ready")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2))
                .foregroundColor(.green)
                .cornerRadius(4)
        case .syncing:
            ProgressView()
                .scaleEffect(0.8)
        case .synced:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        case .authenticating:
            ProgressView()
                .scaleEffect(0.8)
        }
    }
}

// MARK: - SyncResultCard

struct SyncResultCard: View {
    let result: SyncResult
    
    var body: some View {
        HStack {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result.success ? .green : .red)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(result.platform.displayName)
                    .font(.subheadline.weight(.semibold))
                
                Text(result.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if result.success, !result.syncInstructions.isEmpty {
                    Text("Next: \(result.syncInstructions.first ?? "")")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            if let estimatedTime = result.estimatedSyncTime {
                Text(estimatedTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(result.success ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - WorkoutOptionsSheet

struct WorkoutOptionsSheet: View {
    @Binding var options: WorkoutOptions
    let selectedPlatforms: Set<DevicePlatform>
    let onConfirm: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section("Workout Settings") {
                    TextField("Workout Name", text: .init(
                        get: { options.workoutName },
                        set: { newName in 
                            options = WorkoutOptions(
                                workoutName: newName,
                                includeWarmup: options.includeWarmup,
                                includeCooldown: options.includeCooldown,
                                powerTolerance: options.powerTolerance
                            )
                        }
                    ))
                    
                    Toggle("Include Warmup", isOn: .init(
                        get: { options.includeWarmup },
                        set: { newValue in
                            options = WorkoutOptions(
                                workoutName: options.workoutName,
                                includeWarmup: newValue,
                                includeCooldown: options.includeCooldown,
                                powerTolerance: options.powerTolerance
                            )
                        }
                    ))
                    
                    Toggle("Include Cooldown", isOn: .init(
                        get: { options.includeCooldown },
                        set: { newValue in
                            options = WorkoutOptions(
                                workoutName: options.workoutName,
                                includeWarmup: options.includeWarmup,
                                includeCooldown: newValue,
                                powerTolerance: options.powerTolerance
                            )
                        }
                    ))
                    
                    VStack {
                        HStack {
                            Text("Power Tolerance")
                            Spacer()
                            Text("\(Int(options.powerTolerance))%")
                        }
                        
                        Slider(value: .init(
                            get: { options.powerTolerance },
                            set: { newValue in
                                options = WorkoutOptions(
                                    workoutName: options.workoutName,
                                    includeWarmup: options.includeWarmup,
                                    includeCooldown: options.includeCooldown,
                                    powerTolerance: newValue
                                )
                            }
                        ), in: 1...15, step: 1)
                    }
                }
                
                Section("Selected Devices") {
                    ForEach(Array(selectedPlatforms), id: \.self) { platform in
                        HStack {
                            Text(platform.displayName)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .navigationTitle("Workout Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onConfirm()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - ShareSheet (UIActivityViewController wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}