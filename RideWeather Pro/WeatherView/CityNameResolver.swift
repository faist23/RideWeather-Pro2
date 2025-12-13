//
//  CityNameResolver.swift
//

import Foundation
import MapKit
import CoreLocation
import SwiftUI

struct CityNameResolver {
    func getCityName(for location: CLLocation, into viewModel: WeatherViewModel) async {
        do {
            let request = MKLocalSearch.Request()
            request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
            let search = MKLocalSearch(request: request)
            let response = try await search.start()

            if let item = response.mapItems.first {
                let name = item.name ?? "Unknown Location"
                await MainActor.run { withAnimation { viewModel.locationName = name } }
            }
        } catch {
            print("City name lookup failed: \(error)")
            await MainActor.run {
                if viewModel.locationName == "Loading location..." {
                    viewModel.locationName = "Unknown Location"
                }
            }
        }
    }
}
