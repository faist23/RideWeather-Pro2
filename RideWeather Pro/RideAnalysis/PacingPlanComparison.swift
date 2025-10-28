//
//  PacingPlanComparison.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 10/27/25.
//


//
//  PacingPlanComparison.swift
//  RideWeather Pro
//

import Foundation

struct PacingPlanComparison: Codable, Identifiable {
    let id: UUID
    let date: Date
    let routeName: String
    
    // Plan vs Actual
    let plannedTime: TimeInterval
    let actualTime: TimeInterval
    let timeDifference: TimeInterval // negative = faster than plan
    
    let plannedPower: Double
    let actualPower: Double
    let powerDifference: Double
    
    // Segment-by-segment comparison
    let segmentResults: [SegmentResult]
    
    // Overall metrics
    let powerEfficiency: Double // 0-100%
    let performanceGrade: PerformanceGrade
    let totalPotentialTimeSavings: TimeInterval
    
    // Insights
    let strengths: [String]
    let improvements: [String]
    
    init(id: UUID = UUID(), date: Date = Date(), routeName: String,
         plannedTime: TimeInterval, actualTime: TimeInterval,
         plannedPower: Double, actualPower: Double,
         segmentResults: [SegmentResult], powerEfficiency: Double,
         performanceGrade: PerformanceGrade, totalPotentialTimeSavings: TimeInterval,
         strengths: [String], improvements: [String]) {
        self.id = id
        self.date = date
        self.routeName = routeName
        self.plannedTime = plannedTime
        self.actualTime = actualTime
        self.timeDifference = actualTime - plannedTime
        self.plannedPower = plannedPower
        self.actualPower = actualPower
        self.powerDifference = actualPower - plannedPower
        self.segmentResults = segmentResults
        self.powerEfficiency = powerEfficiency
        self.performanceGrade = performanceGrade
        self.totalPotentialTimeSavings = totalPotentialTimeSavings
        self.strengths = strengths
        self.improvements = improvements
    }
    
    struct SegmentResult: Codable, Identifiable {
        let id: UUID
        let segmentIndex: Int
        let segmentName: String
        let plannedPower: Double
        let actualPower: Double
        let deviation: Double // percentage
        let timeLost: TimeInterval
        let grade: SegmentGrade
        
        init(id: UUID = UUID(), segmentIndex: Int, segmentName: String,
             plannedPower: Double, actualPower: Double, deviation: Double,
             timeLost: TimeInterval, grade: SegmentGrade) {
            self.id = id
            self.segmentIndex = segmentIndex
            self.segmentName = segmentName
            self.plannedPower = plannedPower
            self.actualPower = actualPower
            self.deviation = deviation
            self.timeLost = timeLost
            self.grade = grade
        }
    }
    
    enum SegmentGrade: String, Codable {
        case excellent = "A+"
        case good = "A"
        case acceptable = "B"
        case needsWork = "C"
        case poor = "D"
        
        var color: String {
            switch self {
            case .excellent: return "#4CAF50"
            case .good: return "#8BC34A"
            case .acceptable: return "#FFC107"
            case .needsWork: return "#FF9800"
            case .poor: return "#F44336"
            }
        }
    }
    
    enum PerformanceGrade: String, Codable {
        case aPlusPlus = "A++"
        case aPlus = "A+"
        case a = "A"
        case aMinus = "A-"
        case bPlus = "B+"
        case b = "B"
        case bMinus = "B-"
        case cPlus = "C+"
        case c = "C"
        case cMinus = "C-"
        case d = "D"
        case f = "F"
        
        var color: String {
            switch self {
            case .aPlusPlus, .aPlus: return "#4CAF50"
            case .a, .aMinus: return "#8BC34A"
            case .bPlus, .b: return "#CDDC39"
            case .bMinus, .cPlus: return "#FFC107"
            case .c, .cMinus: return "#FF9800"
            case .d, .f: return "#F44336"
            }
        }
    }
}