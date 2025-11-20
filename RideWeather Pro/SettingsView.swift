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
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Core Configuration
                // Keep core app behavior at the top level
                Section {
                    Picker("Unit System", selection: $viewModel.settings.units) {
                        ForEach(UnitSystem.allCases) { unit in
                            Text(unit.description).tag(unit)
                        }
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
                
                // MARK: - Rider Profile (Dynamic)
                // This changes based on the selected method
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
                
                Section("Connections") {
                    NavigationLink(destination: IntegrationsSettingsView()) {
                        HStack {
                            Label("Integrations", systemImage: "link")
                            Spacer()
                            // Show a little badge if connected
                            HStack(spacing: 4) {
                                if stravaService.isAuthenticated { ConnectionBadge(color: .orange) }
                                if garminService.isAuthenticated { ConnectionBadge(color: .blue) }
                                if wahooService.isAuthenticated { ConnectionBadge(color: .cyan) }
                                if healthManager.isAuthorized { ConnectionBadge(color: .red) }
                            }
                        }
                    }
                }
                
                // MARK: - Data Management
                Section("Data & Storage") {
                    NavigationLink {
                        TrainingLoadView()
                    } label: {
                        Label("View Training Load", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    
                    HStack {
                        Text("Storage Used")
                        Spacer()
                        Text(TrainingLoadManager.shared.getStorageInfo())
                            .foregroundStyle(.secondary)
                    }
                    
                    Button(role: .destructive) {
                        TrainingLoadManager.shared.clearAll()
                        // Clear sync date from UserDefaults
                        UserDefaults.standard.removeObject(forKey: "lastTrainingLoadSync")
                        print("🗑️ Cleared all training load data and sync date")
                    } label: {
                        Label("Reset Training Load Data", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }

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
            .scrollContentBackground(.hidden) // Hide default background for custom styling
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
                        // Save settings and trigger recalculation if needed
                        viewModel.recalculateWithNewSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Inline Sub-Views for Dynamic Content
    
    private var averageSpeedSettings: some View {
        Group {
            HStack {
                Text("Average Speed")
                Spacer()
                Text("\(String(format: "%.1f", viewModel.settings.averageSpeed)) \(viewModel.settings.units.speedUnitAbbreviation)")
                    .foregroundStyle(.secondary)
            }
            
            // 2. A Stepper is much better for precise adjustments
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
            }
            .padding(.vertical, 4)
            
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
                // FIXED: Logic to force elevation ON when power-based
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
    
    var body: some View {
        Form {
            // Apple Health
            Section {
                if healthManager.isAuthorized {
                    HStack {
                        Label("Connected to Health", systemImage: "heart.fill")
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Refresh") {
                            Task { await healthManager.fetchReadinessData() }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                } else {
                    Button {
                        Task {
                            isConnectingHealth = true
                            _ = await healthManager.requestAuthorization() // Explicitly ignore result
                            isConnectingHealth = false
                        }
                    } label: {
                        if isConnectingHealth { ProgressView() } else { Text("Connect Apple Health") }
                    }
                }
            } header: {
                Text("Apple Health")
            } footer: {
                Text("Syncs HRV, Resting HR, and Sleep for readiness insights.")
            }
            
            // Strava
            Section("Strava") {
                if stravaService.isAuthenticated {
                    HStack {
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
                    
                    // Auto-Sync Weight Toggle
                    Toggle(isOn: $viewModel.settings.autoSyncWeightFromStrava) {
                        Text("Auto-Sync Weight")
                    }
                } else {
                    Button {
                        stravaService.authenticate()
                    } label: {
                        Label("Connect with Strava", systemImage: "link")
                    }
                }
            }
            
            // Garmin
            Section("Garmin") {
                if garminService.isAuthenticated {
                    HStack {
                        Text(garminService.athleteName ?? "Connected")
                        Spacer()
                        Button("Disconnect", role: .destructive) { garminService.disconnect() }
                            .buttonStyle(.borderless)
                    }
                } else {
                    Button {
                        garminService.authenticate()
                    } label: {
                        Label("Connect with Garmin", systemImage: "link")
                    }
                }
                if let error = garminService.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            
            // Wahoo
            Section("Wahoo") {
                if wahooService.isAuthenticated {
                    HStack {
                        Text(wahooService.athleteName ?? "Connected")
                        Spacer()
                        Button("Disconnect", role: .destructive) { wahooService.disconnect() }
                            .buttonStyle(.borderless)
                    }
                } else {
                    Button {
                        wahooService.authenticate()
                    } label: {
                        Label("Connect with Wahoo", systemImage: "link")
                    }
                }
                if let error = wahooService.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Integrations")
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

/*
//
// SettingsView.swift - Enhanced with FTP and Power-Based Analysis
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var stravaService: StravaService
    @EnvironmentObject var wahooService: WahooService
    @EnvironmentObject var garminService: GarminService
    @EnvironmentObject var healthManager: HealthKitManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var isConnectingHealth = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Units Section
                Section("Units") {
                    Picker("Unit System", selection: $viewModel.settings.units) {
                        ForEach(UnitSystem.allCases) { unit in
                            Text(unit.description).tag(unit)
                        }
                    }
                }
                
                // MARK: - Speed Calculation Method
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Speed Calculation Method")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        
                        Picker("Method", selection: $viewModel.settings.speedCalculationMethod) {
                            ForEach(AppSettings.SpeedCalculationMethod.allCases) { method in
                                Text(method.description).tag(method)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        Text(viewModel.settings.speedCalculationMethod.detailDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Route Analysis Method")
                } footer: {
                    Text("Power-based analysis provides more accurate time estimates by accounting for terrain, wind resistance, and your fitness level.")
                }
                
                // MARK: - Speed/Power Configuration
                if viewModel.settings.speedCalculationMethod == .averageSpeed {
                    Section("Average Speed") {
                        HStack {
                            Text("Average Speed")
                            Spacer()
                            Text("\(String(format: "%.1f", viewModel.settings.averageSpeed)) \(viewModel.settings.units.speedUnitAbbreviation)")
                                .foregroundStyle(.secondary)
                        }
                        
                        // 2. A Stepper is much better for precise adjustments
                        Stepper(
                            "Average Speed",
                            value: $viewModel.settings.averageSpeed,
                            in: viewModel.settings.units == .metric ? 10...40 : 6...25,
                            step: 0.1
                        )
                        .labelsHidden() // Hides the "Average Speed" label to avoid repetition
                    }
                } else {
                    // MARK: - Power-Based Configuration
                    Section {
                        // FTP Setting
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
                            
                            Text("Your maximum sustainable power for 1 hour. Test on a trainer or estimate from recent rides.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                    } header: {
                        Text("Power Settings")
                    }
                    
                    // --- THIS IS THE RESTORED/FIXED SECTION ---
                    Section {
                        // Body Weight
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Body Weight")
                                Spacer()
                                // MODIFIED: Format to one decimal place
                                Text("\(viewModel.settings.bodyWeightInUserUnits, specifier: "%.1f") \(viewModel.settings.units.weightSymbol)")
                                    .foregroundStyle(.secondary)
                            }
                            
                            Slider(
                                value: $viewModel.settings.bodyWeightInUserUnits,
                                in: viewModel.settings.units == .metric ? 40...150 : 90...330,
                                // MODIFIED: Step by 0.1
                                step: 0.1
                            )
                        }
                        
                        // Bike Weight
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Bike + Equipment Weight")
                                Spacer()
                                // MODIFIED: Format to one decimal place
                                Text("\(viewModel.settings.bikeWeightInUserUnits, specifier: "%.1f") \(viewModel.settings.units.weightSymbol)")
                                    .foregroundStyle(.secondary)
                            }
                            
                            Slider(
                                value: $viewModel.settings.bikeWeightInUserUnits,
                                in: viewModel.settings.units == .metric ? 5...25 : 10...55,
                                // MODIFIED: Step by 0.1
                                step: 0.1
                            )
                            
                            // MODIFIED: Format total to one decimal place
                            Text("Total weight: \(String(format: "%.1f", viewModel.settings.totalWeightKg * (viewModel.settings.units == .metric ? 1 : 2.20462))) \(viewModel.settings.units.weightSymbol)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                    } header: {
                        Text("Weight Settings")
                    } footer: {
                        Text("Weight affects climbing speed and rolling resistance calculations.")
                    }
                    
                }
                
                // MARK: - Temperature Preferences
                Section("Temperature Preferences") {
                    HStack {
                        Text("Ideal Temperature")
                        Spacer()
                        Text("\(Int(viewModel.settings.idealTemperature))\(viewModel.settings.units.tempSymbol)")
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(
                        value: $viewModel.settings.idealTemperature,
                        in: viewModel.settings.units == .metric ? 10...35 : 50...95,
                        step: 1
                    )
                    
                    Picker("Temperature Tolerance", selection: $viewModel.settings.temperatureTolerance) {
                        ForEach(AppSettings.TemperatureTolerance.allCases) { tolerance in
                            Text(tolerance.description).tag(tolerance)
                        }
                    }
                }
                
                // MARK: - NEW Safety Warnings Section
                Section("Safety Warnings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Cold Weather Warning", isOn: $viewModel.settings.enableColdWeatherWarning)
                        Text("Get a high-priority warning if temperatures on your route drop below a set threshold.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if viewModel.settings.enableColdWeatherWarning {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Warning Threshold")
                                Spacer()
                                Text("\(Int(viewModel.settings.coldWeatherWarningThreshold))\(viewModel.settings.units.tempSymbol)")
                                    .foregroundStyle(.secondary)
                            }
                            
                            Slider(
                                value: $viewModel.settings.coldWeatherWarningThreshold,
                                in: viewModel.settings.units == .metric ? 0...15 : 32...60,
                                step: 1
                            )
                        }
                    }
                }

                // MARK: - Riding Preferences Section
                Section("Riding Preferences") {
/*                    VStack(alignment: .leading, spacing: 12) {
                        Text("Primary Goal")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        
                        Picker("Primary Goal", selection: $viewModel.settings.primaryRidingGoal) {
                            ForEach(AppSettings.RidingGoal.allCases) { goal in
                                Text(goal.description).tag(goal)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        Text(goalExplanation(for: viewModel.settings.primaryRidingGoal))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }*/
                    
                    Picker("Wind Tolerance", selection: $viewModel.settings.windTolerance) {
                        ForEach(AppSettings.WindTolerance.allCases) { tolerance in
                            Text(tolerance.description).tag(tolerance)
                        }
                    }
                }
                
                // MARK: - Schedule Preferences Section
                Section("Schedule Preferences") {
                    Picker("Wake Up Preference", selection: $viewModel.settings.wakeUpEarliness) {
                        ForEach(AppSettings.WakeUpPreference.allCases) { preference in
                            Text(preference.description).tag(preference)
                        }
                    }
                    
                    Text("This affects how early we'll suggest start times for better conditions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // MARK: - Advanced Route Options
                Section("Advanced Route Options") {
                    Toggle("Include Rest Stops", isOn: $viewModel.settings.includeRestStops)
                    
                    if viewModel.settings.includeRestStops {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Number of stops")
                                Spacer()
                                Text("\(viewModel.settings.restStopCount)")
                                    .foregroundStyle(.secondary)
                            }
                            
                            Stepper(
                                "",
                                value: $viewModel.settings.restStopCount,
                                in: 1...10
                            )
                            .labelsHidden()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Duration per stop")
                                    Spacer()
                                    Text("\(viewModel.settings.restStopDuration) min")
                                        .foregroundStyle(.secondary)
                                }
                                
                                Slider(
                                    value: Binding(
                                        get: { Double(viewModel.settings.restStopDuration) },
                                        set: { viewModel.settings.restStopDuration = Int($0) }
                                    ),
                                    in: 5...60,
                                    step: 5
                                )
                            }
                            
                            Text("Adds \(viewModel.settings.restStopCount * viewModel.settings.restStopDuration) minutes total to ride time.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Consider Elevation", isOn: $viewModel.settings.considerElevation)
                        
                        if viewModel.settings.speedCalculationMethod == .powerBased{
                            Text("Power analysis automatically includes elevation effects")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Adjusts speed calculations for elevation changes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Fueling Preferences") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Max Carbs per Hour")
                            Spacer()
                            Text("\(Int(viewModel.settings.maxCarbsPerHour))g")
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(
                            value: $viewModel.settings.maxCarbsPerHour,
                            in: 30...120,
                            step: 10
                        )
                        
                        Text("Trained athletes can tolerate 90-120g/hr. Start lower if untested.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
//                    Toggle("Prefer Liquid Fueling", isOn: $viewModel.settings.preferLiquids)
//                    Toggle("Avoid Gluten", isOn: $viewModel.settings.avoidGluten)
//                    Toggle("Avoid Caffeine", isOn: $viewModel.settings.avoidCaffeine)
                }

                Section("Apple Health") { // <-- ADD THIS ENTIRE SECTION
                    if healthManager.isAuthorized {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.red)
                                Text("Connected to Health")
                                    .font(.headline)
                            }
                            Text("Your readiness insights (HRV, RHR, Sleep) are active on the Fitness tab.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Button("Refetch Health Data") {
                                Task {
                                    await healthManager.fetchReadinessData()
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Connect Apple Health to get smarter readiness insights by correlating your training load with HRV, Resting HR, and Sleep.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Button {
                                Task {
                                    isConnectingHealth = true
                                    await healthManager.requestAuthorization()
                                    isConnectingHealth = false
                                }
                            } label: {
                                if isConnectingHealth {
                                    ProgressView()
                                } else {
                                    Text("Connect to Apple Health")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(isConnectingHealth)
                        }
                    }
                }

                Section("Strava") {
                    if stravaService.isAuthenticated {
                        HStack(spacing: 12) {
                            StravaLogo()
                                .frame(width: 60, height: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Connected to Strava")
                                    .font(.headline)
                                if let name = stravaService.athleteName {
                                    Text(name)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button(role: .destructive) {
                                stravaService.disconnect()
                            } label: {
                                Text("Disconnect")
                            }
                        }
                        
                        // --- THIS IS THE AUTO-SYNC TOGGLE ---
                        Toggle(isOn: $viewModel.settings.autoSyncWeightFromStrava) {
                            Text("Auto-Sync Weight from Strava")
                        }
                        .tint(.orange)
                        
                        if viewModel.settings.autoSyncWeightFromStrava {
                            Text("Weight will be updated automatically once per day when the app is opened.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        // --- END TOGGLE ---

                    } else {
                        Button {
                            stravaService.authenticate()
                        } label: {
                            HStack(spacing: 12) {
                                StravaLogo()
                                    .frame(width: 30, height: 30)
                                Text("Connect with Strava")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
                
                Section("Garmin") {
                    if garminService.isAuthenticated {
                        HStack(spacing: 12) {
                            Image("garmin_logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 50)
                                .foregroundColor(.primary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Connected to Garmin")
                                    .font(.headline)
                                if let name = garminService.athleteName {
                                    Text(name).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                garminService.disconnect()
                            } label: { Text("Disconnect") }
                        }
                    } else {
                        Button {
                            garminService.authenticate()
                        } label: {
                            HStack(spacing: 12) {
                                Image("garmin_logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 80, height: 50)
                                Text("Connect with Garmin").fontWeight(.semibold)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                    
                    if let error = garminService.errorMessage {
                        Text("Error: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Section("Wahoo") {
                    if wahooService.isAuthenticated {
                        HStack(spacing: 12) {
                            Image("wahoo_logo") // Wahoo icon
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Connected to Wahoo")
                                    .font(.headline)
                                if let name = wahooService.athleteName {
                                    Text(name).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                wahooService.disconnect()
                            } label: { Text("Disconnect") }
                        }
                    } else {
                        Button {
                            wahooService.authenticate()
                        } label: {
                            HStack(spacing: 12) {
                                Image("wahoo_logo") // Wahoo icon
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                               Text("Connect with Wahoo").fontWeight(.semibold)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                    
                    if let error = wahooService.errorMessage {
                        Text("Error: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Section("Training Load") {
                    NavigationLink {
                        TrainingLoadView()
                    } label: {
                        Label("View Training Load", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    
                    // Storage info
                    HStack {
                        Text("Storage Used")
                        Spacer()
                        Text(TrainingLoadManager.shared.getStorageInfo())
                            .foregroundStyle(.secondary)
                    }
                    
                    Button(role: .destructive) {
                        TrainingLoadManager.shared.clearAll()
                        // Clear sync date from UserDefaults
                        UserDefaults.standard.removeObject(forKey: "lastTrainingLoadSync")
                        
                        print("🗑️ Cleared all training load data and sync date")
                    } label: {
                        Label("Reset Training Load Data", systemImage: "trash")
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.buildNumber ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden) // ← ADD THIS to hide default Form background
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
                        // Save settings and trigger recalculation if needed
                        viewModel.recalculateWithNewSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Helper Function for Goal Explanations
    private func goalExplanation(for goal: AppSettings.RidingGoal) -> String {
        switch goal {
        case .commute:
            return "Prioritizes reliability, safety, and arriving in good condition. Focuses on predictable timing and minimizing weather-related delays."
        case .performance:
            return "Optimizes for speed, power output, and training effectiveness. Emphasizes wind conditions, temperature efficiency, and energy conservation."
        case .enjoyment:
            return "Maximizes comfort, scenic conditions, and pleasant riding experience. Prioritizes ideal temperatures, gentle lighting, and minimal weather stress."
        }
    }
}

// MARK: - Bundle Extension for Build Number
extension Bundle {
    var buildNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}

// MARK: - Strava Logo View
struct StravaLogo: View {
    var body: some View {
        Image("connect_strava_logo")
            .resizable()
            .renderingMode(.original) // preserve colors
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
    }
}

extension WeatherViewModel {
    static var preview: WeatherViewModel {
        let vm = WeatherViewModel()
        // set up fake data if desired
        return vm
    }
}
*/
