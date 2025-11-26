//
//  GarminImportExplainerView.swift
//  Replaces GarminActivityImportView with helpful explanation
//

import SwiftUI

struct GarminImportExplainerView: View {
    @EnvironmentObject var garminService: GarminService
    @EnvironmentObject var stravaService: StravaService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image("garmin_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 60)
                        
                        Text("Import Garmin Activities")
                            .font(.title2.bold())
                        
                        Text("Choose how you'd like to import your Garmin rides")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    
                    // Option 1: Via Strava (Recommended)
                    if stravaService.isAuthenticated {
                        recommendedOption
                    } else {
                        connectStravaOption
                    }
                    
                    Divider()
                    
                    // Option 2: Manual Import
                    manualImportOption
                    
                    // Why no automatic Garmin import?
                    Spacer().frame(height: 20)
                    
                    technicalExplanation
                }
                .padding(24)
            }
            .navigationTitle("Garmin Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var recommendedOption: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Text("Recommended")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.yellow)
            }
            
            Text("Automatic via Strava")
                .font(.headline)
            
            Text("Your Garmin activities automatically sync to Strava, and we import them from there.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                StepRow(number: 1, text: "Connect Garmin to Strava (one-time setup)")
                StepRow(number: 2, text: "Activities auto-sync: Garmin → Strava → RideWeather Pro")
                StepRow(number: 3, text: "Import directly from the Strava tab")
            }
            .padding(.vertical, 8)
            
            Button {
                if let url = URL(string: "https://www.strava.com/settings/apps") {
                    openURL(url)
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.up.forward.app")
                    Text("Connect Garmin to Strava")
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 2)
        )
    }
    
    private var connectStravaOption: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Text("Best Option")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.yellow)
            }
            
            Text("Automatic via Strava")
                .font(.headline)
            
            Text("Connect both Strava and Garmin for automatic activity sync.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                StepRow(number: 1, text: "Connect your Strava account in Settings")
                StepRow(number: 2, text: "Link Garmin to Strava (one-time)")
                StepRow(number: 3, text: "Activities auto-sync from Garmin → Strava → Here")
            }
            .padding(.vertical, 8)
            
            HStack(spacing: 12) {
                Button {
                    dismiss()
                    // User should go to Settings to connect Strava
                } label: {
                    HStack {
                        Image("strava_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 16)
                        Text("Connect Strava")
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                
                Button {
                    if let url = URL(string: "https://www.strava.com/settings/apps") {
                        openURL(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "link")
                        Text("Link Garmin")
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 2)
        )
    }
    
    private var manualImportOption: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual File Import")
                .font(.headline)
            
            Text("Download activities from Garmin Connect and import them here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                StepRow(number: 1, text: "Open Garmin Connect website with a computer")
                StepRow(number: 2, text: "Find your activity → Settings → Export File")
                StepRow(number: 3, text: "Save zipped file to Files")
                StepRow(number: 4, text: "Unzip downloaded file")
                StepRow(number: 5, text: "Tap 'Import GPX or FIT File' on main screen")
            }
            .padding(.vertical, 8)
            
            Button {
                if let url = URL(string: "https://connect.garmin.com") {
                    openURL(url)
                }
            } label: {
                HStack {
                    Image(systemName: "safari")
                    Text("Open Garmin Connect")
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private var technicalExplanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text("Why no direct Garmin import?")
                    .font(.subheadline.weight(.semibold))
            }
            
            Text("Garmin's Health API requires a backend server to receive activity notifications. Direct app-to-Garmin activity sync isn't supported for iOS apps without server infrastructure.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("The Strava bridge is the recommended approach used by many fitness apps, or you can manually import FIT files.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
        )
    }
}

struct StepRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
}

#Preview {
    GarminImportExplainerView()
        .environmentObject(GarminService())
        .environmentObject(StravaService())
}
