//
//  StemNoteView.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 11/20/25.
//

import SwiftUI
import Charts

struct StemNoteView: View {
    let pacingPlan: PacingPlan
    let settings: AppSettings
    
    // CONFIGURATION
    private let maxRows: Int = 25
    
    struct StemRow: Identifiable {
        let id = UUID()
        let startDistance: Double
        let segmentDistance: Double
        let type: PowerRouteSegment.SegmentType
        let power: Int
        let duration: TimeInterval
        let isKeySegment: Bool
        let avgGradient: Double?
        let avgHeadwind: Double?
    }
    
    var rows: [StemRow] {
        // Re-instantiate generator every time to ensure clean state
        let generator = StemNoteGenerator(plan: pacingPlan, settings: settings, maxRows: maxRows)
        return generator.generate()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. HEADER
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RIDE PLAN")
                        .font(.system(size: 28, weight: .black))
                        .textCase(.uppercase)
                    
                    Text(settings.speedCalculationMethod == .powerBased ?
                         "Avg: \(Int(pacingPlan.averagePower))W | NP: \(Int(pacingPlan.normalizedPower))W" :
                         "Target Speed: \(String(format: "%.1f", settings.averageSpeed)) \(settings.units.speedSymbol)")
                        .font(.system(size: 14, weight: .bold))
                        .opacity(0.9)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(formatTotalDistance(pacingPlan.totalDistance)))")
                        .font(.system(size: 32, weight: .heavy))
                    Text(settings.units == .metric ? "KM" : "MI")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .padding(16)
            .background(Color.black)
            .foregroundColor(.white)
            
            // 2. ELEVATION PROFILE
            StemProfileView(plan: pacingPlan, settings: settings)
                .frame(height: 80)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .background(Color.white)
                .id(pacingPlan.startTime) // Force redraw if plan changes
            
            // 3. COLUMN HEADERS
            HStack {
                Text(settings.units == .metric ? "KM" : "MI")
                    .frame(width: 50, alignment: .leading)
                Text("SEGMENT")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("TIME")
                    .frame(width: 50, alignment: .trailing)
                Text("WATTS")
                    .frame(width: 70, alignment: .trailing)
            }
            .font(.system(size: 12, weight: .heavy))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(white: 0.9))
            
            // 4. ROWS
            ForEach(Array(rows.prefix(maxRows).enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 0) {
                    // Start Distance
                    Text(formatDistance(row.startDistance))
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 50, alignment: .leading)
                        .foregroundColor(.secondary)
                    
                    // Segment Info
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: row.type))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                        
                        HStack(spacing: 4) {
                            Text(formatSegmentLength(row.segmentDistance, type: row.type))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(row.isKeySegment ? .black : .secondary)
                                .textCase(.uppercase)
                            
                            if let grad = row.avgGradient, abs(grad) > 0.01, row.type != .flat {
                                Text("(\(String(format: "%.0f", abs(grad * 100)))%)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Duration
                    Text(formatTime(row.duration))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                    
                    // Watts + Wind
                    HStack(spacing: 2) {
                        Text("\(row.power)")
                            .font(.system(size: 22, weight: .black))
                        
                        if let wind = row.avgHeadwind, wind > 4.5 {
                            Image(systemName: "wind")
                                .font(.system(size: 12))
                                .foregroundColor(.black)
                        }
                    }
                    .frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    row.isKeySegment ? Color.orange.opacity(0.25) :
                        (index % 2 == 0 ? Color.white : Color(white: 0.95))
                )
                .foregroundColor(.black)
            }
            
            // Overflow
            if rows.count > maxRows {
                Text("... \(rows.count - maxRows) more segments ...")
                    .font(.system(size: 10))
                    .padding(4)
                    .frame(maxWidth: .infinity)
                    .background(Color(white: 0.95))
            }
            
            // 5. FOOTER
            HStack(spacing: 12) {
                Image(systemName: "drop.fill")
                Text("DRINK 1 BOTTLE / HR")
                Spacer()
                if settings.speedCalculationMethod == .powerBased {
                    Text("EAT \(Int(settings.maxCarbsPerHour))g CARB / HR")
                    Image(systemName: "birthday.cake.fill")
                }
            }
            .font(.system(size: 12, weight: .bold))
            .padding(12)
            .background(Color.black)
            .foregroundColor(.white)
        }
        .frame(width: 375)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }
    
    // MARK: - Formatters
    private func formatTotalDistance(_ km: Double) -> Double {
        settings.units == .metric ? km : km * 0.621371
    }
    
    private func formatDistance(_ km: Double) -> String {
        let val = settings.units == .metric ? km : km * 0.621371
        return String(format: "%.1f", val)
    }
    
    private func formatSegmentLength(_ dist: Double, type: PowerRouteSegment.SegmentType) -> String {
        let val = settings.units == .metric ? dist : dist * 0.621371
        let unit = settings.units == .metric ? "km" : "mi"
        
        if type == .climb { return "CLIMB \(String(format: "%.1f", val))\(unit)" }
        if type == .descent { return "DESCEND \(String(format: "%.1f", val))\(unit)" }
        return "FLAT \(String(format: "%.1f", val))\(unit)"
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds / 60)
        if m > 60 {
            let h = m / 60
            let rem = m % 60
            return "\(h)h\(rem)"
        }
        return "\(m)m"
    }
    
    private func icon(for type: PowerRouteSegment.SegmentType) -> String {
        switch type {
        case .climb: return "mountain.2.fill"
        case .descent: return "arrow.down.forward"
        case .flat, .rolling: return "arrow.forward"
        }
    }
}

// MARK: - Stem Profile View
struct StemProfileView: View {
    let plan: PacingPlan
    let settings: AppSettings
    
    struct Point: Identifiable {
        let id = UUID()
        let dist: Double
        let elev: Double
        let type: PowerRouteSegment.SegmentType
    }
    
    var points: [Point] {
        var data: [Point] = []
        var currentDist: Double = 0
        var currentElev: Double = 0
        
        data.append(Point(dist: 0, elev: 0, type: .flat))
        
        for segment in plan.segments {
            let segmentDist = settings.units == .metric ? segment.distanceKm : (segment.distanceKm * 0.621371)
            let riseMeters = segment.originalSegment.elevationGrade * (segment.distanceKm * 1000)
            let riseUserUnits = settings.units == .metric ? riseMeters : (riseMeters * 3.28084)
            
            currentDist += segmentDist
            currentElev += riseUserUnits
            
            data.append(Point(dist: currentDist, elev: currentElev, type: segment.originalSegment.segmentType))
        }
        return data
    }
    
    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("Dist", point.dist), y: .value("Elev", point.elev))
                .foregroundStyle(LinearGradient(colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.linear)
            
            LineMark(x: .value("Dist", point.dist), y: .value("Elev", point.elev))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(Color.black)
                .interpolationMethod(.linear)
            
            // Highlight Climbs on the chart
            if point.type == .climb {
                PointMark(x: .value("Dist", point.dist), y: .value("Elev", point.elev))
                    .symbolSize(0)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                AxisTick()
                if let d = value.as(Double.self) {
                    AxisValueLabel("\(Int(d))")
                }
            }
        }
        .chartYAxis(.hidden)
        .padding(.horizontal, 16)
    }
}

// MARK: - Robust Generator Class

private class StemNoteGenerator {
    let plan: PacingPlan
    let settings: AppSettings
    let ftp: Double
    
    var result: [StemNoteView.StemRow] = []
    
    // Accumulators
    var bufferDist: Double = 0
    var bufferTime: Double = 0
    var bufferWork: Double = 0
    var bufferWeightedGrade: Double = 0
    var bufferWeightedHeadwind: Double = 0
    var bufferStartDist: Double = 0
    
    // Config
    let targetChunkDistance: Double
    let isLongRide: Bool
    
    init(plan: PacingPlan, settings: AppSettings, maxRows: Int) {
        self.plan = plan
        self.settings = settings
        self.ftp = Double(settings.functionalThresholdPower)
        
        let totalDistKm = plan.totalDistance
        self.isLongRide = totalDistKm > 80.0
        
        // Calculate chunk size to fill the page (~maxRows)
        // For 36 miles: 36 / 25 = 1.44 miles/chunk -> Clamped to minChunk (3.0) -> 3.0 miles
        // For 92 miles: 92 / 25 = 3.68 miles/chunk -> 3.68 miles
        let calculatedChunk = totalDistKm / Double(maxRows)
        
        let minChunk = settings.units == .metric ? 10.0 : (5.0 * 1.60934) // ~5 miles
        self.targetChunkDistance = max(minChunk, calculatedChunk)
    }
    
    private var currentTotalDistance: Double {
        if let last = result.last {
            return last.startDistance + last.segmentDistance
        }
        return 0.0
    }
    
    func generate() -> [StemNoteView.StemRow] {
        
        for segment in plan.segments {
            let dist = segment.distanceKm
            let power = segment.targetPower
            var type = segment.originalSegment.segmentType
            if type == .rolling { type = .flat }
            
            let grade = segment.originalSegment.elevationGrade
            let headwind = segment.originalSegment.averageHeadwindMps
            
            // --- 1. IS THIS A MAJOR EVENT? ---
            var isMajorEvent = false
            
            if type == .climb {
                // Distance: Is it long?
                let longThreshold = isLongRide ? 2.5 : 0.3 // 1.5mi vs 0.2mi
                if dist >= longThreshold { isMajorEvent = true }
                
                // Intensity: Is it HARD? (Watts > FTP)
                // Lowered threshold to catch your 188W climb
                let intensity = power / ftp
                if isLongRide {
                    // Long ride: >105% FTP (VO2 Max efforts)
                    if intensity > 1.05 && dist > 0.5 { isMajorEvent = true }
                } else {
                    // Short ride: >85% FTP (Tempo/Threshold)
                    if intensity > 0.85 { isMajorEvent = true }
                }
            } else if type == .descent {
                // Only major if very long
                let descentThreshold = isLongRide ? 5.0 : 2.0
                if dist >= descentThreshold { isMajorEvent = true }
            }
            
            // --- 2. PROCESSING ---
            
            if isMajorEvent {
                // A. Flush any pending buffer
                flush()
                
                // B. Add the Major Event directly
                let start = currentTotalDistance
                result.append(StemNoteView.StemRow(
                    startDistance: start,
                    segmentDistance: dist,
                    type: type,
                    power: Int(power),
                    duration: segment.estimatedTime,
                    isKeySegment: true,
                    avgGradient: grade,
                    avgHeadwind: headwind
                ))
                
                // C. Update buffer start for next segments
                bufferStartDist = currentTotalDistance
            }
            else {
                // It's "Noise" or "General Terrain"
                
                // Initialize buffer if empty
                if bufferDist == 0 {
                    bufferStartDist = currentTotalDistance
                }
                
                // Accumulate
                bufferDist += dist
                bufferTime += segment.estimatedTime
                bufferWork += (power * segment.estimatedTime)
                bufferWeightedGrade += (grade * dist)
                bufferWeightedHeadwind += (headwind * dist)
                
                // Flush if we hit the size target
                if bufferDist >= targetChunkDistance {
                    flush()
                }
            }
        }
        
        // Final flush
        flush()
        return result
    }
    
    private func flush() {
        guard bufferDist > 0 else { return }
        
        let avgPower = bufferWork / bufferTime
        let avgGrade = bufferWeightedGrade / bufferDist
        let avgHeadwind = bufferWeightedHeadwind / bufferDist
        
        result.append(StemNoteView.StemRow(
            startDistance: bufferStartDist,
            segmentDistance: bufferDist,
            type: .flat, // Aggregated minor terrain defaults to "Flat/Rolling"
            power: Int(avgPower),
            duration: bufferTime,
            isKeySegment: false,
            avgGradient: avgGrade,
            avgHeadwind: avgHeadwind
        ))
        
        // Reset
        bufferDist = 0
        bufferTime = 0
        bufferWork = 0
        bufferWeightedGrade = 0
        bufferWeightedHeadwind = 0
    }
}
