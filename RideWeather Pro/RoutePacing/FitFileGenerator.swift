//
//  FitFileGenerator.swift
//  RideWeather Pro
//

import Foundation
import FitSDK // Import the SDK you just added

struct FitFileGenerator {

    /// Generates a FIT file as binary Data from a StructuredWorkout object.
    /// - Parameter workout: The workout plan to be converted.
    /// - Returns: The binary Data of the resulting .FIT file.
    func generate(from workout: StructuredWorkout) throws -> Data {
        
        // 1. Initialize the FIT file encoder
        let encoder = FitEncoder(version: .v20)
        
        // 2. Write required file header messages
        let fileIdMsg = FileIdMessage(
            type: .workout,
            manufacturer: .development, // Use .development for testing
            product: 0,
            serialNumber: 0,
            timeCreated: FitTime(date: workout.metadata.createdDate)
        )
        encoder.write(fileIdMsg)
        
        // 3. Write the main workout message with its name
        let workoutMsg = WorkoutMessage(
            name: workout.name,
            sport: .cycling,
            capabilities: 0
        )
        encoder.write(workoutMsg)
        
        // 4. Loop through your steps and convert them to FIT WorkoutStep messages
        for step in workout.steps {
            var stepMsg = WorkoutStepMessage()
            
            stepMsg.messageIndex = UInt16(step.order)
            stepMsg.name = step.description
            
            // Set the intensity based on your step type
            switch step.type {
            case .rest:
                stepMsg.intensity = .rest
            default:
                stepMsg.intensity = .active
            }
            
            // --- Translate Duration ---
            switch step.duration.type {
            case .time:
                stepMsg.durationType = .time
                // Duration value for time is in seconds x 1000
                stepMsg.durationValue = UInt32(step.duration.value * 1000)
            case .distance:
                stepMsg.durationType = .distance
                // Duration value for distance is in meters
                stepMsg.durationValue = UInt32(step.duration.value)
            case .open:
                stepMsg.durationType = .open
            default:
                // Handle other cases or default to open
                stepMsg.durationType = .open
            }
            
            // --- Translate Target ---
            switch step.target.type {
            case .power:
                stepMsg.targetType = .power
                // Use a custom power range target
                stepMsg.targetValue = 0 // A value of 0 indicates a custom range
                
                // IMPORTANT: The FIT protocol requires a 1000W offset for power values.
                stepMsg.customTargetValueLow = UInt32(step.target.minValue + 1000)
                stepMsg.customTargetValueHigh = UInt32(step.target.maxValue + 1000)
            
            case .heartRate:
                stepMsg.targetType = .heartRate
                stepMsg.targetValue = 0 // Custom range
                // Heart rate offset is 100 bpm
                stepMsg.customTargetValueLow = UInt32(step.target.minValue + 100)
                stepMsg.customTargetValueHigh = UInt32(step.target.maxValue + 100)
                
            default:
                stepMsg.targetType = .open
            }
            
            encoder.write(stepMsg)
        }
        
        // 5. Finalize the file and return the binary data
        guard let fitData = encoder.close() else {
            throw DeviceSyncError.fileGenerationFailed("Encoder failed to close and produce data.")
        }
        
        return fitData
    }
}