//
// SettingsView.swift - Enhanced with FTP and Power-Based Analysis
// Refactored for Modern iOS Navigation Architecture
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var stravaService: StravaService
    @EnvironmentObject var wahooService: WahooService
    @EnvironmentObject var garminService: GarminService
    @EnvironmentObject var healthManager: HealthKitManager
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var dataSourceManager = DataSourceManager.shared
    @State private var lastRefresh = Date() // Forces UI update

    // Track storage strings manually to force updates
    @State private var trainingStorageText: String = ""
    @State private var wellnessStorageText: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Core Configuration
                Section {
                    Picker("Unit System", selection: $viewModel.settings.units) {
                        ForEach(UnitSystem.allCases) { unit in
                            Text(unit.description).tag(unit)
                        }
                    }
                    .onChange(of: viewModel.settings.units) { _, newUnits in
                        viewModel.settings.timeCheckpointIntervalKm = newUnits == .metric ? 10.0 : 8.05
                    }
                    Picker("Analysis Method", selection: $viewModel.settings.speedCalculationMethod) {
                        ForEach(AppSettings.SpeedCalculationMethod.allCases) { method in
                            Text(method.description).tag(method)
                        }
                    }
                } header: {
                    Text("Configuration")
                } footer: {
                    if viewModel.settings.speedCalculationMethod == .powerBased {
                        Text("Power-based analysis accounts for terrain, wind, and weight.")
                    } else {
                        Text("Average speed provides a simple duration estimate.")
                    }
                }
                
                // MARK: - Rider Profile
                Section("Rider Profile") {
                    if viewModel.settings.speedCalculationMethod == .averageSpeed {
                        averageSpeedSettings
                    } else {
                        powerProfileSettings
                    }
                }
                
                // MARK: - Sub-Menus for Details
                Section("Customization") {
                    NavigationLink(destination: PreferencesSettingsView(settings: $viewModel.settings)) {
                        Label("Preferences", systemImage: "slider.horizontal.3")
                    }
                    
                    NavigationLink(destination: RouteSettingsView(settings: $viewModel.settings)) {
                        Label("Route Planning", systemImage: "map")
                    }
                }
                
                // MARK: - NEW: Data Sources Section
                Section("Data & Tracking") {
                    NavigationLink(destination: DataSourceSettingsView()) {
                        HStack {
                            Label("Data Sources", systemImage: "chart.bar.doc.horizontal")
                            Spacer()
                            dataSourceBadges
                        }
                    }
                    
                    NavigationLink(destination: IntegrationsSettingsView()) {
                        HStack {
                            Label("Integrations", systemImage: "link")
                            Spacer()
                            connectionBadges
                        }
                    }
                }
                
                // MARK: - Data Management
                Section("Storage") {
                    NavigationLink {
                        TrainingLoadView()
                    } label: {
                        Label("View Training Load", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    
                    HStack {
                        Text("Training Data")
                        Spacer()
                        Text(trainingStorageText) // Use State
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Wellness Data")
                        Spacer()
                        Text(wellnessStorageText) // Use State
                            .foregroundStyle(.secondary)
                    }
                    
                    Button(role: .destructive) {
                        // 1. Clear Data
                        TrainingLoadManager.shared.clearAll()
                        WellnessManager.shared.clearAll()
                        
                        // 2. Clear Sync State
                        UserDefaults.standard.removeObject(forKey: "lastTrainingLoadSync")
                        UserDefaults.standard.removeObject(forKey: "wellnessLastSync")
                        UserDefaults.standard.removeObject(forKey: "lastWellnessSyncDate")
                        
                        print("🗑️ Cleared all training and wellness data")
                        
                        // 3. Force UI Update Immediately
                        updateStorageInfo()
                        
                        // 4. Notify other views
                        NotificationCenter.default.post(name: .dataSourceChanged, object: nil)
                        
                    } label: {
                        Label("Reset All Data", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
                .id(lastRefresh)
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(Bundle.main.buildNumber ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .animatedBackground(
                gradient: .settingsBackground,
                showDecoration: true,
                decorationColor: .white,
                decorationIntensity: 0.05
            )
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        viewModel.recalculateWithNewSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Update storage text
                updateStorageInfo()
                
                // Auto-configure data sources on first launch if needed
                let status = dataSourceManager.validateConfiguration(
                    stravaConnected: stravaService.isAuthenticated,
                    healthConnected: healthManager.isAuthorized,
                    garminConnected: garminService.isAuthenticated
                )
                
                if !status.isValid {
                    dataSourceManager.autoConfigureFromConnections(
                        stravaConnected: stravaService.isAuthenticated,
                        healthConnected: healthManager.isAuthorized,
                        garminConnected: garminService.isAuthenticated
                    )
                }
            }
        }
    }
    
    // MARK: - Data Source Badges
    
    private var dataSourceBadges: some View {
        HStack(spacing: 4) {
            // Training load badge
            Image(systemName: "figure.run.circle.fill")
                .foregroundColor(trainingLoadColor)
                .font(.caption)
            
            // Wellness badge
            Image(systemName: "heart.circle.fill")
                .foregroundColor(wellnessColor)
                .font(.caption)
        }
    }
    
    private var trainingLoadColor: Color {
        switch dataSourceManager.configuration.trainingLoadSource {
        case .strava: return stravaService.isAuthenticated ? .orange : .gray
        case .appleHealth: return healthManager.isAuthorized ? .red : .gray
        case .garmin: return garminService.isAuthenticated ? .blue : .gray
        case .manual: return .purple
        }
    }
    
    private var wellnessColor: Color {
        switch dataSourceManager.configuration.wellnessSource {
        case .appleHealth: return healthManager.isAuthorized ? .red : .gray
        case .garmin: return garminService.isAuthenticated ? .blue : .gray
        case .none: return .gray
        }
    }
    
    private var connectionBadges: some View {
        HStack(spacing: 4) {
            if stravaService.isAuthenticated { ConnectionBadge(color: .orange) }
            if garminService.isAuthenticated { ConnectionBadge(color: .blue) }
            if wahooService.isAuthenticated { ConnectionBadge(color: .cyan) }
            if healthManager.isAuthorized { ConnectionBadge(color: .red) }
        }
    }
    
    // MARK: - Inline Sub-Views
    
    private var averageSpeedSettings: some View {
        Group {
            HStack {
                Text("Average Speed")
                Spacer()
                Text("\(String(format: "%.1f", viewModel.settings.averageSpeed)) \(viewModel.settings.units.speedUnitAbbreviation)")
                    .foregroundStyle(.secondary)
            }
            
            Stepper(
                "Average Speed",
                value: $viewModel.settings.averageSpeed,
                in: viewModel.settings.units == .metric ? 10...40 : 6...25,
                step: 0.1
            )
            .labelsHidden()
        }
    }
    
    private var powerProfileSettings: some View {
        Group {
            // FTP
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Functional Threshold Power")
                    Spacer()
                    Text("\(viewModel.settings.functionalThresholdPower) watts")
                        .foregroundStyle(.secondary)
                }
                
                Slider(
                    value: Binding(
                        get: { Double(viewModel.settings.functionalThresholdPower) },
                        set: { viewModel.settings.functionalThresholdPower = Int($0) }
                    ),
                    in: 100...450,
                    step: 1
                )
                
                Text("Your maximum sustainable power for 1 hour.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            
            // Body Weight
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Body Weight")
                    Spacer()
                    Text("\(viewModel.settings.bodyWeightInUserUnits, specifier: "%.1f") \(viewModel.settings.units.weightSymbol)")
                        .foregroundStyle(.secondary)
                }
                
                Slider(
                    value: $viewModel.settings.bodyWeightInUserUnits,
                    in: viewModel.settings.units == .metric ? 40...150 : 90...330,
                    step: 0.1
                )
                .disabled(viewModel.settings.weightSource != .manual)
                .opacity(viewModel.settings.weightSource != .manual ? 0.6 : 1.0)
                
                Picker("Update from", selection: $viewModel.settings.weightSource) {
                    ForEach(AppSettings.WeightSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.settings.weightSource) { _, newSource in
                    Task {
                        await performWeightSync(source: newSource)
                    }
                }
                
                if viewModel.settings.weightSource == .strava && !stravaService.isAuthenticated {
                    Text("⚠️ Connect Strava in Integrations to sync")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if viewModel.settings.weightSource == .healthKit && !healthManager.isAuthorized {
                    Text("⚠️ Connect Health in Integrations to sync")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.vertical, 4)
            .task {
                await performWeightSync(source: viewModel.settings.weightSource)
            }
            
            // Bike Weight
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Bike + Equipment Weight")
                    Spacer()
                    Text("\(viewModel.settings.bikeWeightInUserUnits, specifier: "%.1f") \(viewModel.settings.units.weightSymbol)")
                        .foregroundStyle(.secondary)
                }
                
                Slider(
                    value: $viewModel.settings.bikeWeightInUserUnits,
                    in: viewModel.settings.units == .metric ? 5...25 : 10...55,
                    step: 0.1
                )
                
                Text("Total System Weight: \(String(format: "%.1f", viewModel.settings.totalWeightKg * (viewModel.settings.units == .metric ? 1 : 2.20462))) \(viewModel.settings.units.weightSymbol)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Sync Helper
    
    private func performWeightSync(source: AppSettings.WeightSource) async {
        var newWeight: Double? = nil
        
        switch source {
        case .strava:
            if stravaService.isAuthenticated {
                do {
                    newWeight = try await stravaService.fetchAthleteWeight()
                } catch {
                    print("Settings: Strava weight sync failed: \(error)")
                }
            }
        case .healthKit:
            if healthManager.isAuthorized {
                newWeight = await healthManager.fetchLatestWeight()
            }
        case .manual:
            return
        }
        
        if let weight = newWeight, weight > 0 {
            await MainActor.run {
                viewModel.settings.bodyWeight = weight
                let _ = viewModel.settings.bodyWeightInUserUnits
            }
        }
    }
    
    // MARK: - UI Helpers
    
    private func updateStorageInfo() {
        trainingStorageText = TrainingLoadManager.shared.getStorageInfo()
        wellnessStorageText = WellnessManager.shared.getStorageInfo()
    }
}



// MARK: - Sub-View: Preferences
struct PreferencesSettingsView: View {
    @Binding var settings: AppSettings
    
    var body: some View {
        Form {
            Section("Temperature Comfort") {
                HStack {
                    Text("Ideal Temperature")
                    Spacer()
                    Text("\(Int(settings.idealTemperature))\(settings.units.tempSymbol)")
                        .foregroundStyle(.secondary)
                }
                
                Slider(
                    value: $settings.idealTemperature,
                    in: settings.units == .metric ? 10...35 : 50...95,
                    step: 1
                )
                
                Picker("Tolerance", selection: $settings.temperatureTolerance) {
                    ForEach(AppSettings.TemperatureTolerance.allCases) { tolerance in
                        Text(tolerance.description).tag(tolerance)
                    }
                }
            }
            
            Section("Safety Warnings") {
                Toggle("Cold Weather Warning", isOn: $settings.enableColdWeatherWarning)
                
                if settings.enableColdWeatherWarning {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Warning Threshold")
                            Spacer()
                            Text("\(Int(settings.coldWeatherWarningThreshold))\(settings.units.tempSymbol)")
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(
                            value: $settings.coldWeatherWarningThreshold,
                            in: settings.units == .metric ? 0...15 : 32...60,
                            step: 1
                        )
                        Text("Get a warning if temps drop below this.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section("Riding Style") {
                /* // COMMENTED OUT: Primary Goal adds little value (default is Performance)
                Picker("Primary Goal", selection: $settings.primaryRidingGoal) {
                    ForEach(AppSettings.RidingGoal.allCases) { goal in
                        Text(goal.description).tag(goal)
                    }
                }
                */
                
                Picker("Wind Tolerance", selection: $settings.windTolerance) {
                    ForEach(AppSettings.WindTolerance.allCases) { tolerance in
                        Text(tolerance.description).tag(tolerance)
                    }
                }
            }
            
            Section("Schedule") {
                Picker("Wake Up Preference", selection: $settings.wakeUpEarliness) {
                    ForEach(AppSettings.WakeUpPreference.allCases) { preference in
                        Text(preference.description).tag(preference)
                    }
                }
            }
        }
        .navigationTitle("Preferences")
    }
}

// MARK: - Sub-View: Route Planning
struct RouteSettingsView: View {
    @Binding var settings: AppSettings
    
    var body: some View {
        Form {
            Section("Stop Strategy") {
                Toggle("Include Rest Stops", isOn: $settings.includeRestStops)
                
                if settings.includeRestStops {
                    Stepper("Number of stops: \(settings.restStopCount)", value: $settings.restStopCount, in: 1...10)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Duration per stop")
                            Spacer()
                            Text("\(settings.restStopDuration) min")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings.restStopDuration) },
                                set: { settings.restStopDuration = Int($0) }
                            ),
                            in: 5...60,
                            step: 5
                        )
                    }
                }
            }
            
            Section("Elevation") {
                // Logic to force elevation ON when power-based
                Toggle("Consider Elevation", isOn: Binding(
                    get: {
                        settings.speedCalculationMethod == .powerBased ? true : settings.considerElevation
                    },
                    set: { newValue in
                        // Only allow changing if NOT power-based
                        if settings.speedCalculationMethod != .powerBased {
                            settings.considerElevation = newValue
                        }
                    }
                ))
                .disabled(settings.speedCalculationMethod == .powerBased) // Visually disable
                .tint(settings.speedCalculationMethod == .powerBased ? .gray : .blue) // Optional: Make it look "locked on"
                
                Text(settings.speedCalculationMethod == .powerBased ?
                     "Power analysis requires elevation data for physics calculations." :
                     "Adjusts average speed estimates based on climbing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Only show Fueling Strategy if Power-Based Analysis is enabled
            if settings.speedCalculationMethod == .powerBased {
                Section("Fueling Strategy") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Max Carbs per Hour")
                            Spacer()
                            Text("\(Int(settings.maxCarbsPerHour))g")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.maxCarbsPerHour, in: 30...120, step: 10)
                    }
                    
                    /* // COMMENTED OUT: Removing specific dietary toggles for cleaner UI
                    Toggle("Prefer Liquid Fueling", isOn: $settings.preferLiquids)
                    Toggle("Avoid Gluten", isOn: $settings.avoidGluten)
                    Toggle("Avoid Caffeine", isOn: $settings.avoidCaffeine)
                    */
                }
            }
            
            Section("Time Checkpoints for Pacing Plans") {
                Toggle("Enable Time Checkpoints", isOn: $settings.enableTimeCheckpoints)
                
                if settings.enableTimeCheckpoints {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Checkpoint Interval")
                            Spacer()
                            Text(String(format: "%.1f \(settings.units == .metric ? "km" : "mi")", settings.timeCheckpointIntervalInUserUnits))
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { settings.timeCheckpointIntervalInUserUnits },
                                set: { settings.timeCheckpointIntervalInUserUnits = $0 }
                            ),
                            in: settings.units == .metric ? 1...20 : 1...12,
                            step: 0.5
                        )
                        
                        Text("Your bike computer will show expected arrival time every \(String(format: "%.1f", settings.timeCheckpointIntervalInUserUnits)) \(settings.units == .metric ? "km" : "mi")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Route Planning")
    }
}

// MARK: - Sub-View: Integrations
struct IntegrationsSettingsView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var stravaService: StravaService
    @EnvironmentObject var wahooService: WahooService
    @EnvironmentObject var garminService: GarminService
    @EnvironmentObject var healthManager: HealthKitManager
    
    @State private var isConnectingHealth = false

    @State private var garminPermissions: [String] = []
    @State private var checkingPermissions = false
    
    // Strava Brand Color
    private let stravaOrange = Color(hex: "FC5200")
    
    var body: some View {
        Form {
            // ==================================================================
            // APPLE HEALTH
            // ==================================================================
            Section {
                if healthManager.isAuthorized {
                    HStack {
                        Image(systemName: "heart.fill")
 //                           .resizable()
 //                           .scaledToFit()
                            .frame(width: 35, height: 35)
                            .foregroundColor(.red)
                        
                        VStack(alignment: .leading) {
                            Text("Apple Health")
                                .font(.headline)
                            Text("Connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Disconnect", role: .destructive) {
                            healthManager.disconnect()
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    Button {
                        Task {
                            isConnectingHealth = true
                            _ = await healthManager.requestAuthorization() // Explicitly ignore result
                            isConnectingHealth = false
                        }
                    } label: {
                        if isConnectingHealth {
                            ProgressView()
                        } else {
                            HStack {
                                Image(systemName: "apple.logo")
                                    .font(.title2)
                                    .foregroundColor(.primary)
                                Text("Connect Apple Health")
                            }
                        }
                    }
                }
            } header: {
                Text("Apple Health")
            } footer: {
                Text("Syncs HRV, Resting HR, and Sleep for readiness insights.")
            }
            
            // ==================================================================
            // STRAVA
            // ==================================================================
            Section {
                if stravaService.isAuthenticated {
                    HStack {
                        Image("strava_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 35, height: 35)
                            
                        VStack(alignment: .leading) {
                            Text(stravaService.athleteName ?? "Connected")
                                .font(.headline)
                            Text("Authenticated")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Disconnect", role: .destructive) { stravaService.disconnect() }
                            .buttonStyle(.borderless)
                    }
                                        
                } else {
                    Button {
                        stravaService.authenticate()
                    } label: {
                        // Updated with Logo and Color
                        HStack {
                            Image("strava_logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 35, height: 35)
                            
                            Text("Connect with Strava")
                                .foregroundColor(stravaOrange)
                        }
                    }
                }
            } header: {
                Text("Strava")
            } footer: {
                // Enhanced description
                VStack(alignment: .leading, spacing: 8) {
                    Text("What This Enables:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    Text("• Import saved routes for weather forecasting")
                    Text("• Import completed rides for performance analysis")
                    Text("• Automatic body weight sync")
                    Text("• Training load tracking from your activities")
                }
                .font(.caption)
            }
            
            // ==================================================================
            // GARMIN
            // ==================================================================
            Section {
                 if garminService.isAuthenticated {
                     HStack {
                         Image("garmin_logo")
                             .resizable()
                             .scaledToFit()
                             .frame(width: 35, height: 35)
                         
                         Text(garminService.athleteName ?? "Connected")
                         Spacer()
                         Button("Disconnect", role: .destructive) {
                             garminService.disconnect()
                         }
                         .buttonStyle(.borderless)
                     }
                     
                     if checkingPermissions {
                         HStack {
                             ProgressView()
                                 .controlSize(.small)
                             Text("Checking permissions...")
                                 .font(.caption)
                                 .foregroundStyle(.secondary)
                         }
                     } /* else if !garminPermissions.isEmpty {
                         VStack(alignment: .leading, spacing: 8) {
                             Text("Permissions:")
                                 .font(.caption)
                                 .foregroundStyle(.secondary)
                             
                             ForEach(garminPermissions, id: \.self) { permission in
                                 HStack(spacing: 4) {
                                     Image(systemName: "checkmark.circle.fill")
                                         .foregroundStyle(.green)
                                         .font(.caption2)
                                     Text(permission)
                                         .font(.caption2)
                                         .foregroundStyle(.secondary)
                                 }
                             }
                         }
                         .padding(.vertical, 4)
                     }*/
                     
                 } else {
                     Button {
                         garminService.authenticate()
                     } label: {
                         HStack {
                             Image("garmin_logo")
                                 .resizable()
                                 .scaledToFit()
                                 .frame(width: 35, height: 35)
                                 .foregroundColor(.primary)
                             
                             Text("Connect with Garmin")
                         }
                         
                     }
                 }
                 
                 if let error = garminService.errorMessage {
                     Text(error).font(.caption).foregroundStyle(.red)
                 }
             } header: {
                 Text("Garmin")
             } footer: {
                 // Enhanced description explaining what actually works
                 VStack(alignment: .leading, spacing: 8) {
                     Text("What This Enables:")
                         .font(.caption)
                         .fontWeight(.semibold)
                     
                     Text("• Upload weather-aware pacing plans directly to your Garmin device")
                         .fontWeight(.medium) // Highlight the main feature
                     Text("• Wellness data sync (HRV, sleep, stress) for readiness insights")
                     Text("• Training load tracking from your activities")
                     
                     Divider()
                         .padding(.vertical, 4)
                     
                     Text("Note: To import routes or analyze rides, export FIT files from Garmin Connect and use 'Import File'.")
                         .font(.caption2)
                         .foregroundStyle(.secondary)
                         .italic()
                 }
                 .font(.caption)
             }

             // ==================================================================
             // WAHOO
             // ==================================================================
             Section {
                 if wahooService.isAuthenticated {
                     HStack {
                         Image("wahoo_logo")
                             .resizable()
                             .scaledToFit()
                             .frame(width: 35, height: 35)
                         
                         Text(wahooService.athleteName ?? "Connected")
                         Spacer()
                         Button("Disconnect", role: .destructive) {
                             wahooService.disconnect()
                         }
                         .buttonStyle(.borderless)
                     }
                 } else {
                     Button {
                         wahooService.authenticate()
                     } label: {
                         HStack {
                             Image("wahoo_logo")
                                 .resizable()
                                 .scaledToFit()
                                 .frame(width: 35, height: 35)
                             
                             Text("Connect with Wahoo")
                         }
                     }
                 }
                 if let error = wahooService.errorMessage {
                     Text(error).font(.caption).foregroundStyle(.red)
                 }
             } header: {
                 Text("Wahoo")
             } footer: {
                 // Enhanced description
                 VStack(alignment: .leading, spacing: 8) {
                     Text("What This Enables:")
                         .font(.caption)
                         .fontWeight(.semibold)
                     
                     Text("• Upload weather-aware pacing plans directly to your Wahoo device")
                         .fontWeight(.medium) // Highlight the main feature
                     Text("• Import saved routes for weather forecasting")
                     Text("• Import completed rides for performance analysis")
                     Text("• Access your workout library")
                     Text("• Training load tracking from your activities")
                 }
                 .font(.caption)
             }
         }
         .navigationTitle("Integrations")
         .task {
             // Check Garmin permissions when view appears
             if garminService.isAuthenticated && garminPermissions.isEmpty {
                 await checkGarminPermissions()
             }
         }
     }
     
     // Add permission check function
     private func checkGarminPermissions() async {
         checkingPermissions = true
         
         // Use the existing test endpoint to check permissions
         do {
             let token = garminService.currentTokens?.accessToken ?? ""
             let url = URL(string: "https://apis.garmin.com/userPermissions/")!
             var request = URLRequest(url: url)
             request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
             
             let (data, _) = try await URLSession.shared.data(for: request)
             
             if let permissions = try? JSONDecoder().decode([String].self, from: data) {
                 await MainActor.run {
                     garminPermissions = permissions
                     checkingPermissions = false
                 }
             }
         } catch {
             print("Failed to check Garmin permissions: \(error)")
             await MainActor.run {
                 checkingPermissions = false
             }
         }
     }
 }

// MARK: - UI Components
struct ConnectionBadge: View {
    let color: Color
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

// Re-add StravaLogo struct if needed, though Standard Labels are cleaner for settings lists
// Keeping other extensions from original file
extension Bundle {
    var buildNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}



