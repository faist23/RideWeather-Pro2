//
//  CityNameResolver.swift
//

import Foundation
import CoreLocation
import SwiftUI

struct CityNameResolver {
    func getCityName(for location: CLLocation, into viewModel: WeatherViewModel) async {
        let geocoder = CLGeocoder()
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            if let placemark = placemarks.first {
                // Priority: Neighborhood (subLocality) > City (locality) > Area (administrativeArea)
                let name = placemark.subLocality ?? placemark.locality ?? placemark.administrativeArea ?? "Unknown Location"
                
                await MainActor.run {
                    withAnimation {
                        viewModel.locationName = name
                        print("📍 Location resolved to: \(name)")
                    }
                }
            }
        } catch {
            print("Location name lookup failed: \(error.localizedDescription)")
            await MainActor.run {
                if viewModel.locationName == "Loading location..." {
                    viewModel.locationName = "Unknown Location"
                }
            }
        }
    }
}
