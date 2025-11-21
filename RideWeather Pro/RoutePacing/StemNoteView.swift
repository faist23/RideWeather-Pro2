//
//  StemNoteView.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 11/20/25.
//

import SwiftUI

struct StemNoteView: View {
    let pacingPlan: PacingPlan
    let settings: AppSettings
    
    // Helper struct for row data
    struct StemRow: Identifiable {
        let id = UUID()
        let cumulativeDistance: Double
        let segmentDistance: Double
        let type: PowerRouteSegment.SegmentType
        let power: Int
        let duration: TimeInterval
        let isKeySegment: Bool
    }
    
    // MARK: - Adaptive Logic
    var rows: [StemRow] {
        var result: [StemRow] = []
        
        // 1. Calculate Dynamic Chunk Size
        // We want the route to fit in roughly 12 rows (leaving room for header/footer).
        // For 92 miles, this makes chunks ~7.5 miles. For 30 miles, ~2.5 miles.
        let targetRowCount = 12.0
        let minChunkSize = settings.units == .metric ? 5.0 : 3.0
        
        // The chunk size scales with ride length, but never gets too small
        let targetChunkDistance = max(minChunkSize, pacingPlan.totalDistance / targetRowCount)
        
        var bufferDistance: Double = 0
        var bufferDuration: Double = 0
        var bufferWeightedPower: Double = 0
        var bufferStartDistance: Double = 0
        
        // Helper to flush the buffer into a row
        func flushBuffer() {
            if bufferDistance > 0 {
                let avgPower = bufferWeightedPower / bufferDistance
                
                result.append(StemRow(
                    cumulativeDistance: bufferStartDistance + bufferDistance,
                    segmentDistance: bufferDistance,
                    type: .flat, // Aggregated sections are treated as flat/rolling
                    power: Int(avgPower),
                    duration: bufferDuration,
                    isKeySegment: false
                ))
            }
            // Reset buffer
            bufferDistance = 0
            bufferDuration = 0
            bufferWeightedPower = 0
        }
        
        for segment in pacingPlan.segments {
            // 1. Is this a "Key" segment? (Climb or Significant Descent)
            // We ALWAYS break out climbs, regardless of length, because they determine race outcome.
            let isClimb = segment.originalSegment.segmentType == .climb
            
            // Only break out descents if they are long enough to matter (>2km/1.2mi)
            // otherwise fold them into the rolling terrain
            let isSignificantDescent = segment.originalSegment.segmentType == .descent && segment.distanceKm > 2.0
            
            if isClimb || isSignificantDescent {
                flushBuffer()
                
                // Add the special segment immediately
                result.append(StemRow(
                    cumulativeDistance: (result.last?.cumulativeDistance ?? 0) + segment.distanceKm,
                    segmentDistance: segment.distanceKm,
                    type: segment.originalSegment.segmentType,
                    power: Int(segment.targetPower),
                    duration: segment.estimatedTime,
                    isKeySegment: isClimb
                ))
                
                // Update where the next buffer starts
                bufferStartDistance = result.last?.cumulativeDistance ?? 0
            }
            else {
                // 2. It's a flat/rolling/short descent segment. Add to buffer.
                if bufferDistance == 0 {
                    bufferStartDistance = (result.last?.cumulativeDistance ?? 0)
                }
                
                // Standard units accumulation
                let segmentDist = settings.units == .metric ? segment.distanceKm : (segment.distanceKm * 0.621371)
                
                bufferDistance += segmentDist
                bufferDuration += segment.estimatedTime
                bufferWeightedPower += (segment.targetPower * segmentDist)
                
                // 3. If buffer exceeds our DYNAMIC target, flush it
                if bufferDistance >= targetChunkDistance {
                    flushBuffer()
                    bufferStartDistance = (result.last?.cumulativeDistance ?? 0)
                }
            }
        }
        
        // Flush any remaining distance at the end
        flushBuffer()
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // BLACK HEADER
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RACE PLAN")
                        .font(.system(size: 28, weight: .black))
                        .textCase(.uppercase)
                    
                    Text("Avg: \(Int(pacingPlan.averagePower))W | NP: \(Int(pacingPlan.normalizedPower))W")
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
            
            // COLUMN HEADERS
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
            
            // DATA ROWS
            // We remove the prefix(14) limit because the aggregation logic ensures it fits.
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 0) {
                    // Cumulative Marker
                    Text(String(format: "%.1f", row.cumulativeDistance))
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 50, alignment: .leading)
                        .foregroundColor(.secondary)
                    
                    // Icon & Segment Length
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: row.type))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                        
                        Text(formatSegmentLength(row.segmentDistance))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Duration estimate
                    Text(formatTime(row.duration))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                    
                    // POWER TARGET (BIG & BOLD)
                    Text("\(row.power)")
                        .font(.system(size: 22, weight: .black))
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    // Alternating rows, with Orange highlight for Climbs
                    row.isKeySegment ? Color.orange.opacity(0.25) :
                        (index % 2 == 0 ? Color.white : Color(white: 0.95))
                )
                .foregroundColor(.black)
            }
            
            // NUTRITION REMINDER FOOTER
            HStack(spacing: 12) {
                Image(systemName: "drop.fill")
                Text("DRINK 1 BOTTLE / HR")
                Spacer()
                Text("EAT 60g CARB / HR")
                Image(systemName: "birthday.cake.fill")
            }
            .font(.system(size: 12, weight: .bold))
            .padding(12)
            .background(Color.black)
            .foregroundColor(.white)
        }
        .frame(width: 375) // Fixed width for consistency
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }
    
    // MARK: - Formatters
    
    private func formatTotalDistance(_ km: Double) -> Double {
        if settings.units == .metric {
            return km
        } else {
            return km * 0.621371
        }
    }
    
    private func formatSegmentLength(_ dist: Double) -> String {
        let unit = settings.units == .metric ? "km" : "mi"
        return String(format: "%.1f%@", dist, unit)
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
        case .flat: return "arrow.forward"
        case .rolling: return "waveform.path.ecg"
        }
    }
}
