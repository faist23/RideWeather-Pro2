//
//  WahooModels+FITConversion.swift
//  RideWeather Pro
//

import Foundation
import CoreLocation

extension WahooService {
    
    /// Converts Wahoo workout stream data into the app's standard `FITDataPoint` array.
    func convertWahooDataToFITDataPoints(
        workout: WahooWorkoutSummary,
        streams: WahooWorkoutData
    ) -> [FITDataPoint] {
        
        guard let timeData = streams.time, !timeData.isEmpty else {
            return []
        }
        
        let startDate = workout.rideDate ?? Date()
        var dataPoints: [FITDataPoint] = []
        
        let powerData = streams.power
        let heartrateData = streams.heartrate
        let cadenceData = streams.cadence
        let speedData = streams.speed
        let distanceData = streams.distance
        let altitudeData = streams.altitude
        
        // Change from snake_case to camelCase
        let latData = streams.positionLat
        let lonData = streams.positionLong
        
        for i in 0..<timeData.count {
            let timestamp = startDate.addingTimeInterval(timeData[i])
            
            var coordinate: CLLocationCoordinate2D?
            if let lat = latData?[safe: i], let lon = lonData?[safe: i] {
                if lat != 0 && lon != 0 {
                    coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
            }
            
            let dataPoint = FITDataPoint(
                timestamp: timestamp,
                power: powerData?[safe: i].map { Double($0) },
                heartRate: heartrateData?[safe: i],
                cadence: cadenceData?[safe: i],
                speed: speedData?[safe: i],
                distance: distanceData?[safe: i],
                altitude: altitudeData?[safe: i],
                position: coordinate
            )
            
            dataPoints.append(dataPoint)
        }
        
        return dataPoints
    }
}
