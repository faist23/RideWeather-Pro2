//
//  FITFileParser.swift
//  RideWeather Pro
//
//  Real FIT file parsing using native Swift
//

import Foundation
import CoreLocation

// MARK: - FIT File Parser

final class FITFileParser {
    
    enum ParseError: LocalizedError {
        case invalidFileFormat
        case unsupportedVersion
        case corruptedData
        case noActivityData
        
        var errorDescription: String? {
            switch self {
            case .invalidFileFormat: return "Invalid FIT file format"
            case .unsupportedVersion: return "Unsupported FIT file version"
            case .corruptedData: return "FIT file data is corrupted"
            case .noActivityData: return "No activity data found in file"
            }
        }
    }
    
    // MARK: - Public API
    
    func parse(_ fileURL: URL) throws -> ParsedRideFile {
        let data = try Data(contentsOf: fileURL)
        
        // Validate FIT file header
        guard data.count >= 14 else {
            throw ParseError.invalidFileFormat
        }
        
        // Check FIT file signature
        let headerSize = data[0]
        let protocolVersion = data[1]
        
        guard headerSize >= 12, protocolVersion <= 2 else {
            throw ParseError.unsupportedVersion
        }
        
        // Parse records from the file
        let records = try parseRecords(from: data, headerSize: Int(headerSize))
        
        guard !records.isEmpty else {
            throw ParseError.noActivityData
        }
        
        // Calculate metrics
        let startTime = records.first?.timestamp ?? Date()
        let endTime = records.last?.timestamp ?? Date()
        let totalDuration = endTime.timeIntervalSince(startTime)
        
        // Calculate moving time (exclude stops)
        let movingTime = calculateMovingTime(records)
        
        // Calculate total distance
        let totalDistance = records.last?.distance ?? 0
        
        // Determine available data
        let hasPowerData = records.contains { $0.power != nil }
        let hasHeartRateData = records.contains { $0.heartRate != nil }
        let hasGPSData = records.contains { $0.latitude != nil && $0.longitude != nil }
        
        return ParsedRideFile(
            fileName: fileURL.lastPathComponent,
            startTime: startTime,
            endTime: endTime,
            totalDuration: totalDuration,
            movingTime: movingTime,
            totalDistance: totalDistance,
            records: records,
            hasPowerData: hasPowerData,
            hasHeartRateData: hasHeartRateData,
            hasGPSData: hasGPSData
        )
    }
    
    // MARK: - Private Parsing Methods
    
    private func parseRecords(from data: Data, headerSize: Int) throws -> [FITRecord] {
        var records: [FITRecord] = []
        var position = headerSize
        
        // State tracking for record assembly
        var currentTimestamp: Date?
        var currentLatitude: Double?
        var currentLongitude: Double?
        var currentAltitude: Double?
        var currentPower: Int?
        var currentHeartRate: Int?
        var currentCadence: Int?
        var currentSpeed: Double?
        var currentTemperature: Double?
        var currentDistance: Double?
        
        // Message definitions cache
        var messageDefinitions: [UInt8: MessageDefinition] = [:]
        
        while position < data.count {
            guard position < data.count else { break }
            
            let recordHeader = data[position]
            position += 1
            
            let isDefinitionMessage = (recordHeader & 0x40) != 0
            let localMessageType = recordHeader & 0x0F
            
            if isDefinitionMessage {
                // Parse definition message
                let definition = try parseDefinitionMessage(from: data, at: &position)
                messageDefinitions[localMessageType] = definition
            } else {
                // Parse data message
                guard let definition = messageDefinitions[localMessageType] else {
                    // Skip unknown message
                    position += 1
                    continue
                }
                
                let messageData = try parseDataMessage(
                    from: data,
                    at: &position,
                    definition: definition
                )
                
                // Extract fields based on global message number
                switch definition.globalMessageNumber {
                case 20: // Record message
                    if let timestamp = messageData["timestamp"] as? UInt32 {
                        currentTimestamp = fitTimestampToDate(timestamp)
                    }
                    if let lat = messageData["position_lat"] as? Int32 {
                        currentLatitude = semicirclesToDegrees(lat)
                    }
                    if let lon = messageData["position_long"] as? Int32 {
                        currentLongitude = semicirclesToDegrees(lon)
                    }
                    if let alt = messageData["altitude"] as? UInt16 {
                        currentAltitude = Double(alt) / 5.0 - 500.0
                    }
                    if let power = messageData["power"] as? UInt16 {
                        currentPower = Int(power)
                    }
                    if let hr = messageData["heart_rate"] as? UInt8 {
                        currentHeartRate = Int(hr)
                    }
                    if let cadence = messageData["cadence"] as? UInt8 {
                        currentCadence = Int(cadence)
                    }
                    if let speed = messageData["speed"] as? UInt16 {
                        currentSpeed = Double(speed) / 1000.0 // Convert to m/s
                    }
                    if let temp = messageData["temperature"] as? Int8 {
                        currentTemperature = Double(temp)
                    }
                    if let distance = messageData["distance"] as? UInt32 {
                        currentDistance = Double(distance) / 100.0
                    }
                    
                    // Create record if we have timestamp
                    if let timestamp = currentTimestamp {
                        let record = FITRecord(
                            timestamp: timestamp,
                            latitude: currentLatitude,
                            longitude: currentLongitude,
                            altitude: currentAltitude,
                            power: currentPower,
                            heartRate: currentHeartRate,
                            cadence: currentCadence,
                            speed: currentSpeed,
                            temperature: currentTemperature,
                            distance: currentDistance
                        )
                        records.append(record)
                    }
                    
                default:
                    break
                }
            }
        }
        
        return records
    }
    
    private func parseDefinitionMessage(from data: Data, at position: inout Int) throws -> MessageDefinition {
        guard position + 5 <= data.count else {
            throw ParseError.corruptedData
        }
        
        // Skip reserved byte
        position += 1
        
        // Architecture (0 = little endian, 1 = big endian)
        let architecture = data[position]
        position += 1
        
        // Global message number
        let globalMessageNumber: UInt16
        if architecture == 0 {
            globalMessageNumber = UInt16(data[position]) | (UInt16(data[position + 1]) << 8)
        } else {
            globalMessageNumber = (UInt16(data[position]) << 8) | UInt16(data[position + 1])
        }
        position += 2
        
        // Number of fields
        let fieldCount = data[position]
        position += 1
        
        // Parse field definitions
        var fields: [FieldDefinition] = []
        for _ in 0..<fieldCount {
            guard position + 3 <= data.count else {
                throw ParseError.corruptedData
            }
            
            let fieldNumber = data[position]
            let size = data[position + 1]
            let baseType = data[position + 2]
            position += 3
            
            fields.append(FieldDefinition(
                fieldNumber: fieldNumber,
                size: size,
                baseType: baseType
            ))
        }
        
        return MessageDefinition(
            globalMessageNumber: globalMessageNumber,
            fields: fields,
            isLittleEndian: architecture == 0
        )
    }
    
    private func parseDataMessage(
        from data: Data,
        at position: inout Int,
        definition: MessageDefinition
    ) throws -> [String: Any] {
        var fieldData: [String: Any] = [:]
        
        for field in definition.fields {
            guard position + Int(field.size) <= data.count else {
                throw ParseError.corruptedData
            }
            
            let fieldName = getFieldName(
                messageNumber: definition.globalMessageNumber,
                fieldNumber: field.fieldNumber
            )
            
            let value = parseFieldValue(
                from: data,
                at: position,
                size: Int(field.size),
                baseType: field.baseType,
                isLittleEndian: definition.isLittleEndian
            )
            
            if let value = value {
                fieldData[fieldName] = value
            }
            
            position += Int(field.size)
        }
        
        return fieldData
    }
    
    private func parseFieldValue(
        from data: Data,
        at position: Int,
        size: Int,
        baseType: UInt8,
        isLittleEndian: Bool
    ) -> Any? {
        let baseTypeMasked = baseType & 0x1F
        
        switch baseTypeMasked {
        case 0: // enum
            return data[position]
        case 1: // sint8
            return Int8(bitPattern: data[position])
        case 2: // uint8
            return data[position]
        case 0x83: // sint16
            if size >= 2 {
                let value = isLittleEndian
                    ? Int16(data[position]) | (Int16(data[position + 1]) << 8)
                    : (Int16(data[position]) << 8) | Int16(data[position + 1])
                return value
            }
        case 0x84: // uint16
            if size >= 2 {
                let value = isLittleEndian
                    ? UInt16(data[position]) | (UInt16(data[position + 1]) << 8)
                    : (UInt16(data[position]) << 8) | UInt16(data[position + 1])
                return value
            }
        case 0x85: // sint32
            if size >= 4 {
                var value: Int32 = 0
                if isLittleEndian {
                    value = Int32(data[position])
                        | (Int32(data[position + 1]) << 8)
                        | (Int32(data[position + 2]) << 16)
                        | (Int32(data[position + 3]) << 24)
                } else {
                    value = (Int32(data[position]) << 24)
                        | (Int32(data[position + 1]) << 16)
                        | (Int32(data[position + 2]) << 8)
                        | Int32(data[position + 3])
                }
                return value
            }
        case 0x86: // uint32
            if size >= 4 {
                var value: UInt32 = 0
                if isLittleEndian {
                    value = UInt32(data[position])
                        | (UInt32(data[position + 1]) << 8)
                        | (UInt32(data[position + 2]) << 16)
                        | (UInt32(data[position + 3]) << 24)
                } else {
                    value = (UInt32(data[position]) << 24)
                        | (UInt32(data[position + 1]) << 16)
                        | (UInt32(data[position + 2]) << 8)
                        | UInt32(data[position + 3])
                }
                return value
            }
        case 7: // string
            let stringData = data.subdata(in: position..<(position + size))
            if let string = String(data: stringData, encoding: .utf8) {
                return string.trimmingCharacters(in: .controlCharacters)
            }
        default:
            break
        }
        
        return nil
    }
    
    private func getFieldName(messageNumber: UInt16, fieldNumber: UInt8) -> String {
        // Record message (20) field mappings
        if messageNumber == 20 {
            switch fieldNumber {
            case 253: return "timestamp"
            case 0: return "position_lat"
            case 1: return "position_long"
            case 2: return "altitude"
            case 3: return "heart_rate"
            case 4: return "cadence"
            case 5: return "distance"
            case 6: return "speed"
            case 7: return "power"
            case 13: return "temperature"
            default: return "unknown_\(fieldNumber)"
            }
        }
        
        return "field_\(fieldNumber)"
    }
    
    private func fitTimestampToDate(_ timestamp: UInt32) -> Date {
        // FIT timestamp is seconds since UTC 00:00 Dec 31 1989
        let fitEpoch = Date(timeIntervalSince1970: 631065600)
        return fitEpoch.addingTimeInterval(TimeInterval(timestamp))
    }
    
    private func semicirclesToDegrees(_ semicircles: Int32) -> Double {
        return Double(semicircles) * (180.0 / 2147483648.0)
    }
    
    private func calculateMovingTime(_ records: [FITRecord]) -> TimeInterval {
        var movingTime: TimeInterval = 0
        
        for i in 1..<records.count {
            let timeDiff = records[i].timestamp.timeIntervalSince(records[i - 1].timestamp)
            
            // Consider moving if speed > 1 m/s (3.6 km/h)
            if let speed = records[i].speed, speed > 1.0 {
                movingTime += timeDiff
            }
        }
        
        return movingTime
    }
}

// MARK: - Supporting Types

struct MessageDefinition {
    let globalMessageNumber: UInt16
    let fields: [FieldDefinition]
    let isLittleEndian: Bool
}

struct FieldDefinition {
    let fieldNumber: UInt8
    let size: UInt8
    let baseType: UInt8
}

// MARK: - Integration with Existing Code

extension RideFileAnalyzer {
    
    private func parseFITFile(_ fileURL: URL) async throws -> ParsedRideFile {
        let parser = FITFileParser()
        return try parser.parse(fileURL)
    }
}

// MARK: - GPX Parser (Alternative Format)

final class GPXFileParser {
    
    func parse(_ fileURL: URL) throws -> ParsedRideFile {
        let data = try Data(contentsOf: fileURL)
        
        // Basic GPX parsing
        // In production, use XMLParser or a GPX library
        
        var records: [FITRecord] = []
        let startTime = Date()
        
        // Mock implementation - replace with actual GPX parsing
        // A real implementation would parse <trkpt> elements with lat/lon
        // and <extensions> for power/hr data
        
        return ParsedRideFile(
            fileName: fileURL.lastPathComponent,
            startTime: startTime,
            endTime: startTime.addingTimeInterval(3600),
            totalDuration: 3600,
            movingTime: 3500,
            totalDistance: 30000,
            records: records,
            hasPowerData: false,
            hasHeartRateData: false,
            hasGPSData: true
        )
    }
}

// MARK: - Universal File Handler

final class RideFileHandler {
    
    enum FileType {
        case fit
        case gpx
        case tcx
        case unknown
        
        init(fileExtension: String) {
            switch fileExtension.lowercased() {
            case "fit": self = .fit
            case "gpx": self = .gpx
            case "tcx": self = .tcx
            default: self = .unknown
            }
        }
    }
    
    func parseFile(_ fileURL: URL) async throws -> ParsedRideFile {
        let fileType = FileType(fileExtension: fileURL.pathExtension)
        
        switch fileType {
        case .fit:
            let parser = FITFileParser()
            return try parser.parse(fileURL)
            
        case .gpx:
            let parser = GPXFileParser()
            return try parser.parse(fileURL)
            
        case .tcx:
            // TCX parsing would go here
            throw FITFileParser.ParseError.unsupportedVersion
            
        case .unknown:
            throw FITFileParser.ParseError.invalidFileFormat
        }
    }
}

// MARK: - Integration Helper for ViewModel

extension WeatherViewModel {
    
    func analyzeRideFile(_ fileURL: URL, againstPlan plan: PacingPlan) async {
        guard let controller = advancedController else { return }
        
        let analyzer = RideFileAnalyzer(originalPlan: plan, settings: settings)
        await analyzer.analyzeRideFile(fileURL)
        
        // Store analyzer for access from UI
        // You'll need to add this property to WeatherViewModel:
        // @Published var rideAnalyzer: RideFileAnalyzer?
        // self.rideAnalyzer = analyzer
    }
}

// MARK: - Export Analysis Results

extension RideAnalysis {
    
    func exportAsCSV() -> String {
        var csv = "Metric,Value\n"
        csv += "Performance Score,\(Int(performanceScore))\n"
        csv += "Duration,\(parsedFile.totalDuration)\n"
        csv += "Distance,\(parsedFile.totalDistance)\n"
        
        if let metrics = powerMetrics {
            csv += "Average Power,\(Int(metrics.averagePower))\n"
            csv += "Normalized Power,\(Int(metrics.normalizedPower))\n"
            csv += "Intensity Factor,\(String(format: "%.2f", metrics.intensityFactor))\n"
            csv += "TSS,\(Int(metrics.tss))\n"
            csv += "Variability Index,\(String(format: "%.2f", metrics.variabilityIndex))\n"
        }
        
        csv += "\nSegment Comparison\n"
        csv += "Segment,Planned Power,Actual Power,Planned Time,Actual Time,Deviation\n"
        
        for segment in segmentAnalysis {
            csv += "\(segment.segmentName),"
            csv += "\(Int(segment.planned.targetPower)),"
            csv += "\(segment.actual.actualPower.map { String(Int($0)) } ?? "N/A"),"
            csv += "\(Int(segment.planned.targetTime)),"
            csv += "\(Int(segment.actual.actualTime)),"
            csv += "\(segment.deviation.severity.description)\n"
        }
        
        return csv
    }
    
    func exportDetailedReport() -> String {
        var report = """
        ═══════════════════════════════════════════════════════
        RIDE ANALYSIS REPORT
        ═══════════════════════════════════════════════════════
        
        FILE: \(parsedFile.fileName)
        DATE: \(parsedFile.startTime.formatted(date: .long, time: .shortened))
        
        PERFORMANCE SCORE: \(Int(performanceScore))/100
        
        """
        
        report += """
        
        ───────────────────────────────────────────────────────
        RIDE SUMMARY
        ───────────────────────────────────────────────────────
        Duration:       \(formatDuration(parsedFile.totalDuration))
        Moving Time:    \(formatDuration(parsedFile.movingTime))
        Distance:       \(String(format: "%.1f km", parsedFile.totalDistance / 1000))
        Avg Speed:      \(String(format: "%.1f km/h", parsedFile.averageSpeed * 3.6))
        
        """
        
        if let metrics = powerMetrics {
            report += """
            
            ───────────────────────────────────────────────────────
            POWER ANALYSIS
            ───────────────────────────────────────────────────────
            Average Power:      \(Int(metrics.averagePower))W
            Normalized Power:   \(Int(metrics.normalizedPower))W
            Intensity Factor:   \(String(format: "%.2f", metrics.intensityFactor))
            TSS:                \(Int(metrics.tss))
            Variability Index:  \(String(format: "%.2f", metrics.variabilityIndex))
            
            Peak Powers:
            """
            
            for (duration, power) in metrics.peakPowers.sorted(by: { $0.key.seconds < $1.key.seconds }) {
                report += "\n  \(duration.displayString): \(power)W"
            }
        }
        
        report += """
        
        
        ───────────────────────────────────────────────────────
        PACING ANALYSIS
        ───────────────────────────────────────────────────────
        Consistency:    \(Int(paceAnalysis.overallConsistency))%
        Fatigue:        \(paceAnalysis.fatigueDetected ? "Detected" : "None detected")
        
        """
        
        if !insights.isEmpty {
            report += """
            
            ───────────────────────────────────────────────────────
            KEY INSIGHTS
            ───────────────────────────────────────────────────────
            
            """
            
            for insight in insights {
                report += """
                [\(insight.priority == .high ? "HIGH" : insight.priority == .medium ? "MED" : "LOW")] \(insight.title)
                \(insight.description)
                → \(insight.recommendation)
                
                """
            }
        }
        
        if !segmentAnalysis.isEmpty {
            report += """
            
            ───────────────────────────────────────────────────────
            SEGMENT COMPARISON
            ───────────────────────────────────────────────────────
            
            """
            
            for segment in segmentAnalysis {
                report += """
                \(segment.segmentName) - \(segment.deviation.severity.description)
                  Planned: \(Int(segment.planned.targetPower))W, \(formatDuration(segment.planned.targetTime))
                  Actual:  \(segment.actual.actualPower.map { "\(Int($0))W" } ?? "N/A"), \(formatDuration(segment.actual.actualTime))
                  \(segment.analysis)
                
                """
            }
        }
        
        report += """
        ═══════════════════════════════════════════════════════
        End of Report
        ═══════════════════════════════════════════════════════
        """
        
        return report
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}