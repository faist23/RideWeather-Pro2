//
//  GarminCourseFitGenerator.swift
//  RideWeather Pro - Garmin Course FIT File with Power Targets
//

import Foundation
import FITSwiftSDK
import CoreLocation

/// Generates Garmin-compatible Course FIT files with embedded power targets
struct GarminCourseFitGenerator {
    
    enum CourseExportError: LocalizedError {
        case noRoutePoints
        case noPacingPlan
        case invalidData(String)
        case fitSDKError(String)
        
        var errorDescription: String? {
            switch self {
            case .noRoutePoints:
                return "No route points available for export"
            case .noPacingPlan:
                return "No pacing plan available for export"
            case .invalidData(let reason):
                return "Invalid data: \(reason)"
            case .fitSDKError(let reason):
                return "FIT SDK error: \(reason)"
            }
        }
    }
    
    // MARK: - Main Export Function
    
    /// Generates a Garmin Course FIT file with power targets embedded in course points
    func generateCourseFIT(
            routePoints: [EnhancedRoutePoint],
            pacingPlan: PacingPlan,
            courseName: String,
            settings: AppSettings,
            includeRecordMessages: Bool = true // <-- ADD THIS PARAMETER
        ) throws -> Data {
        
        guard !routePoints.isEmpty else {
            throw CourseExportError.noRoutePoints
        }
        
        guard !pacingPlan.segments.isEmpty else {
            throw CourseExportError.noPacingPlan
        }
        
        print("🚴‍♂️ Generating Garmin Course FIT file...")
        print("   Route points: \(routePoints.count)")
        print("   Pacing segments: \(pacingPlan.segments.count)")
        
        let encoder = Encoder()
        
        // 1. Write File ID Message (Course type)
        try writeFileIDMessage(encoder: encoder, courseName: courseName)
        
        // 2. Write Course Message (metadata)
        try writeCourseMessage(encoder: encoder, courseName: courseName, pacingPlan: pacingPlan)
        
            // 3. Write Lap Message (single lap for the entire course)
            try writeLapMessage(encoder: encoder, routePoints: routePoints, pacingPlan: pacingPlan)
            
            // 4. Write Course Points with Power Targets
            try writeCoursePointsWithPower(
                encoder: encoder,
                routePoints: routePoints,
                pacingPlan: pacingPlan
            )
            
            // 5. Write Record Messages (GPS track with power at each point)
            if includeRecordMessages { // <-- ADD THIS IF-STATEMENT
                try writeRecordMessages(
                    encoder: encoder,
                    routePoints: routePoints,
                    pacingPlan: pacingPlan
                )
            }
            
            // 6. Finalize and return data
            let fitData = encoder.close()
            print("✅ Course FIT file generated: \(fitData.count) bytes")
            
            return fitData
        }
    
    // MARK: - Message Writers
    
    private func writeFileIDMessage(encoder: Encoder, courseName: String) throws {
        var fileIdMesg = FileIdMesg()
        
        try fileIdMesg.setType(.course)
        try fileIdMesg.setManufacturer(.development) // Use .development for custom files
        try fileIdMesg.setProduct(0)
        try fileIdMesg.setSerialNumber(UInt32(Date().timeIntervalSince1970))
        try fileIdMesg.setTimeCreated(DateTime(date: Date()))
        
        encoder.write(mesg: fileIdMesg)
    }
    
    private func writeCourseMessage(
        encoder: Encoder,
        courseName: String,
        pacingPlan: PacingPlan
    ) throws {
        var courseMesg = CourseMesg()
        
        // Course name (max 15 characters for Garmin compatibility)
        let safeName = String(courseName.prefix(15))
        try courseMesg.setName(safeName)
        
        // Sport type
        try courseMesg.setSport(.cycling)
        
        encoder.write(mesg: courseMesg)
    }
    
    private func writeLapMessage(
        encoder: Encoder,
        routePoints: [EnhancedRoutePoint],
        pacingPlan: PacingPlan
    ) throws {
        guard let startPoint = routePoints.first,
              let endPoint = routePoints.last else {
            throw CourseExportError.invalidData("Missing route endpoints")
        }
        
        var lapMesg = LapMesg()
        
        // Lap timing
        let startTime = Date()
        try lapMesg.setStartTime(DateTime(date: startTime))
        try lapMesg.setTimestamp(DateTime(date: startTime.addingTimeInterval(pacingPlan.totalTimeMinutes * 60)))
        
        // Lap distance and duration
        try lapMesg.setTotalDistance(endPoint.distance)
        try lapMesg.setTotalTimerTime(pacingPlan.totalTimeMinutes * 60)
        try lapMesg.setTotalElapsedTime(pacingPlan.totalTimeMinutes * 60)
        
        // Lap position
        let startLatSemi = Int32(startPoint.coordinate.latitude * (Double(Int32.max) / 180.0))
        let startLonSemi = Int32(startPoint.coordinate.longitude * (Double(Int32.max) / 180.0))
        try lapMesg.setStartPositionLat(startLatSemi)
        try lapMesg.setStartPositionLong(startLonSemi)
        
        let endLatSemi = Int32(endPoint.coordinate.latitude * (Double(Int32.max) / 180.0))
        let endLonSemi = Int32(endPoint.coordinate.longitude * (Double(Int32.max) / 180.0))
        try lapMesg.setEndPositionLat(endLatSemi)
        try lapMesg.setEndPositionLong(endLonSemi)
        
        // Power metrics
        try lapMesg.setAvgPower(UInt16(pacingPlan.averagePower))
        try lapMesg.setNormalizedPower(UInt16(pacingPlan.normalizedPower))
        
        encoder.write(mesg: lapMesg)
    }
    
    private func writeCoursePointsWithPower(
        encoder: Encoder,
        routePoints: [EnhancedRoutePoint],
        pacingPlan: PacingPlan
    ) throws {
        
        print("📍 Writing course points with power targets...")
        
        // Create course points at segment boundaries
        var messageIndex: UInt16 = 0
        
        for (segmentIndex, segment) in pacingPlan.segments.enumerated() {
            // Find the route point closest to this segment's start
            let segmentStartDistance = segment.originalSegment.startPoint.distance
            
            guard let closestPoint = routePoints.min(by: { point1, point2 in
                abs(point1.distance - segmentStartDistance) < abs(point2.distance - segmentStartDistance)
            }) else {
                continue
            }
            
            var coursePointMesg = CoursePointMesg()
            
            try coursePointMesg.setMessageIndex(messageIndex)
            messageIndex += 1
            
            // Position
            let latSemi = Int32(closestPoint.coordinate.latitude * (Double(Int32.max) / 180.0))
            let lonSemi = Int32(closestPoint.coordinate.longitude * (Double(Int32.max) / 180.0))
            try coursePointMesg.setPositionLat(latSemi)
            try coursePointMesg.setPositionLong(lonSemi)
            
            // Distance
            try coursePointMesg.setDistance(closestPoint.distance)
            
            // Course point name (shows on device)
            let pointName: String
            if segmentIndex == 0 {
                pointName = "Start"
            } else if segmentIndex == pacingPlan.segments.count - 1 {
                pointName = "Finish"
            } else {
                pointName = "S\(segmentIndex + 1)"
            }
            try coursePointMesg.setName(String(pointName.prefix(10)))
            
            // Point type - use generic for power targets
            try coursePointMesg.setType(.generic)
            
            // THIS IS KEY: Store power target in the course point
            // Garmin devices read this to display power targets
            try coursePointMesg.setFavorite(false) // Not a favorite point
            
            // Note: Power target is embedded via the name or notes field
            // since direct power target field doesn't exist in course points
            let powerNote = "\(Int(segment.targetPower))W"
            try coursePointMesg.setName(powerNote)
            
            encoder.write(mesg: coursePointMesg)
        }
        
        print("✅ Wrote \(messageIndex) course points")
    }
    
    private func writeRecordMessages(
        encoder: Encoder,
        routePoints: [EnhancedRoutePoint],
        pacingPlan: PacingPlan
    ) throws {
        
        print("🗺️ Writing record messages (GPS track with power)...")
        
        var currentTime = Date()
        var segmentIndex = 0
        var currentSegment = pacingPlan.segments[0]
        
        for (pointIndex, point) in routePoints.enumerated() {
            // Update segment if we've moved to the next one
            while segmentIndex < pacingPlan.segments.count - 1 {
                let nextSegment = pacingPlan.segments[segmentIndex + 1]
                if point.distance >= nextSegment.originalSegment.startPoint.distance {
                    segmentIndex += 1
                    currentSegment = nextSegment
                } else {
                    break
                }
            }
            
            var recordMesg = RecordMesg()
            
            // Timestamp (simulated based on estimated speed)
            try recordMesg.setTimestamp(DateTime(date: currentTime))
            
            // Position in semicircles (Garmin FIT format)
            let latSemi = Int32(point.coordinate.latitude * (Double(Int32.max) / 180.0))
            let lonSemi = Int32(point.coordinate.longitude * (Double(Int32.max) / 180.0))
            try recordMesg.setPositionLat(latSemi)
            try recordMesg.setPositionLong(lonSemi)
            
            // Distance
            try recordMesg.setDistance(point.distance)
            
            // Elevation (if available)
            if let elevation = point.elevation {
                try recordMesg.setAltitude(elevation)
            }
            
            // **CRITICAL: Target Power at this point**
            // This is what Garmin devices use to display power guidance
            try recordMesg.setPower(UInt16(currentSegment.targetPower))
            
            // Speed (calculated from segment)
            let speedMps = (currentSegment.distanceKm * 1000) / currentSegment.estimatedTime
            try recordMesg.setSpeed(speedMps)
            
            // Heart rate zone (optional - based on power zone)
            let hrZone = mapPowerZoneToHR(powerZone: currentSegment.powerZone)
            try recordMesg.setHeartRate(hrZone)
            
            encoder.write(mesg: recordMesg)
            
            // Increment time for next point
            if pointIndex < routePoints.count - 1 {
                let nextPoint = routePoints[pointIndex + 1]
                let segmentDistance = nextPoint.distance - point.distance
                let timeIncrement = segmentDistance / max(1.0, speedMps)
                currentTime.addTimeInterval(timeIncrement)
            }
        }
        
        print("✅ Wrote \(routePoints.count) record messages")
    }
    
    // MARK: - Helper Functions
    
    private func mapPowerZoneToHR(powerZone: PowerZone) -> UInt8 {
        // Approximate HR mapping based on power zones
        switch powerZone.number {
        case 1: return 110 // Recovery
        case 2: return 130 // Endurance
        case 3: return 150 // Tempo
        case 4: return 165 // Threshold
        case 5: return 180 // VO2 Max
        default: return 140
        }
    }
}
