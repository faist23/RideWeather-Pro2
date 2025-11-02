//
// SettingsView.swift - Enhanced with FTP and Power-Based Analysis
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var stravaService: StravaService // Get the service
    @EnvironmentObject var wahooService: WahooService // Get the service
    @Environment(\.dismiss) private var dismiss
    
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
                    
                    Section {
                        // Body Weight
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Body Weight")
                                Spacer()
                                Text("\(Int(viewModel.settings.bodyWeightInUserUnits)) \(viewModel.settings.units.weightSymbol)")
                                    .foregroundStyle(.secondary)
                            }
                            
                            Slider(
                                value: $viewModel.settings.bodyWeightInUserUnits,
                                in: viewModel.settings.units == .metric ? 40...150 : 90...330,
                                step: viewModel.settings.units == .metric ? 1 : 2
                            )
                        }
                        
                        // Bike Weight
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Bike + Equipment Weight")
                                Spacer()
                                Text("\(Int(viewModel.settings.bikeWeightInUserUnits)) \(viewModel.settings.units.weightSymbol)")
                                    .foregroundStyle(.secondary)
                            }
                            
                            Slider(
                                value: $viewModel.settings.bikeWeightInUserUnits,
                                in: viewModel.settings.units == .metric ? 5...25 : 10...55,
                                step: viewModel.settings.units == .metric ? 0.5 : 1
                            )
                            
                            Text("Total weight: \(Int(viewModel.settings.totalWeightKg * (viewModel.settings.units == .metric ? 1 : 2.20462))) \(viewModel.settings.units.weightSymbol)")
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
                    VStack(alignment: .leading, spacing: 12) {
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
                    }
                    
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
                    
                    Toggle("Prefer Liquid Fueling", isOn: $viewModel.settings.preferLiquids)
                    Toggle("Avoid Gluten", isOn: $viewModel.settings.avoidGluten)
                    Toggle("Avoid Caffeine", isOn: $viewModel.settings.avoidCaffeine)
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
                
                Section("Wahoo") {
                    if wahooService.isAuthenticated {
                        HStack(spacing: 12) {
                            Image(systemName: "w.circle.fill")
                                .font(.title).foregroundStyle(.blue).frame(width: 30, height: 30)
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
                                Image(systemName: "w.circle.fill")
                                    .font(.title).foregroundStyle(.blue).frame(width: 30, height: 30)
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
                    
                    Button(role: .destructive) {
                        TrainingLoadManager.shared.clearAll()
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
