//
//  GarminRouteImportView.swift
//  RideWeather Pro
//
//  Sheet for importing a route from a past Garmin activity
//

import SwiftUI
import CoreLocation
import Combine

// MARK: - Main Import View

struct GarminRouteImportView: View {
    @EnvironmentObject var garminService: GarminService
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.orange)
                
                Text("Import Not Available")
                    .font(.title2)
                    .fontWeight(.bold)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("The official Garmin API does not support fetching past activities without a backend server.")
                        .font(.body)
                    
                    Text("Why?")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    Text("Garmin uses a \"push\" model where activity data is sent to your server when you sync your device. Mobile apps cannot directly fetch activity lists from Garmin.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Alternatives:")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text("If you sync Garmin to Strava, use the Strava import feature")
                        }
                        
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text("Export a .FIT or .GPX file from Garmin Connect and import it manually")
                        }
                        
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text("Use Wahoo for direct activity import (if you have a Wahoo device)")
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .multilineTextAlignment(.leading)
                
                Spacer()
                
                Button("Got It") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Import from Garmin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
