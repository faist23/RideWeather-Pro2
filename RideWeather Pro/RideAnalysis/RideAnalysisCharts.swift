import SwiftUI
import Charts

// MARK: - Common Chart Formatter

/// Formats time in seconds (e.g., 3661.0) into a human-readable string (e.g., "1h1m")
private func timeFormatter(seconds: Double) -> String {
    let hours = Int(seconds) / 3600
    let minutes = (Int(seconds) % 3600) / 60
    
    if hours > 0 {
        return "\(hours)h\(minutes)m"
    } else if minutes > 0 {
        return "\(minutes)m"
    } else {
        return "\(Int(seconds))s"
    }
}

// MARK: - Heart Rate Graph

struct HeartRateGraphCard: View {
    let hrData: [GraphableDataPoint]
    let avgHR: Double
    let elevationData: [GraphableDataPoint]? // <-- ADD THIS
    
    // --- MODIFIED: Calculate min/max for labels ---
    private var dataValues: [Double] { hrData.map { $0.value } }
    private var minHR: Double { dataValues.min() ?? 80 }
    private var maxHR: Double { dataValues.max() ?? 180 }
    
    // Find the min/max for the Y-axis padding
    private var yDomain: ClosedRange<Double> {
        // Add 10% padding
        (minHR * 0.9)...(maxHR * 1.1)
    }
    // --- END MODIFIED ---

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Heart Rate")
                    .font(.headline)
                
                Spacer()
                
                Text("\(Int(avgHR)) BPM AVG")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
            }
            
            ZStack {
                
                // 1. Background Elevation Chart
                if let elevationData {
                    ElevationBackgroundChart(elevationData: elevationData)
                }
                
                // 2. Foreground HR Chart
                Chart(hrData) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.time),
                        y: .value("HR", dataPoint.value)
                    )
                    .foregroundStyle(.red)
                    .interpolationMethod(.monotone)
                    
                    // --- START ADD ---
                    // Add rule mark for the average
                    RuleMark(y: .value("Average", avgHR))
                        .foregroundStyle(.gray.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    
                    // Add rule mark for the max
                    RuleMark(y: .value("Max", maxHR))
                        .foregroundStyle(.gray.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    
                    // Add rule mark for the min
                    RuleMark(y: .value("Min", minHR))
                        .foregroundStyle(.gray.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    // --- END ADD ---
                }
                .frame(height: 150)
                .chartYScale(domain: yDomain)
                .chartYAxis {
                    // --- MODIFIED: Show labels for min, avg, and max ---
                    AxisMarks(values: [minHR, avgHR, maxHR].sorted()) { value in
                        let val = value.as(Double.self) ?? 0
                        AxisValueLabel("\(Int(val))")
                    }
                    // --- END MODIFIED ---
                }
                .chartXAxis {
                    // Show time labels
                    AxisMarks(preset: .automatic, values: .stride(by: .hour)) { value in
                        if let time = value.as(Double.self) {
                            AxisValueLabel(timeFormatter(seconds: time))
                        }
                    }
                }
                .chartPlotStyle { plotArea in // <-- Make plot clear
                    plotArea.background(.clear)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Power Graph

struct PowerGraphCard: View {
    let powerData: [GraphableDataPoint]
    let avgPower: Double
    let elevationData: [GraphableDataPoint]?
    
    // Calculate max for labels
    private var dataValues: [Double] { powerData.map { $0.value } }
    private var maxPower: Double { dataValues.max() ?? 300 }
    
    // Y-axis padding
    private var yMax: Double {
        maxPower * 1.1 // Add 10% padding
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Power")
                    .font(.headline)
                
                Spacer()
                
                Text("\(Int(avgPower)) W AVG")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }
            
            ZStack {
                // 1. Background Elevation Chart
                if let elevationData {
                    ElevationBackgroundChart(elevationData: elevationData)
                }
                
                // 2. Foreground Power Chart (NOW WITH LINE + AREA)
                Chart(powerData) { dataPoint in
                    // Area fill under the line (subtle)
                    AreaMark(
                        x: .value("Time", dataPoint.time),
                        y: .value("Power", dataPoint.value)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [
                                Color.green.opacity(0.3),
                                Color.green.opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                    
                    // Line on top
                    LineMark(
                        x: .value("Time", dataPoint.time),
                        y: .value("Power", dataPoint.value)
                    )
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                    
                    // Average line (dashed)
                    RuleMark(y: .value("Average", avgPower))
                        .foregroundStyle(.gray.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    
                    // Max line (subtle dashed)
                    RuleMark(y: .value("Max", maxPower))
                        .foregroundStyle(.gray.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .frame(height: 150)
                .chartYScale(domain: 0...yMax)
                .chartYAxis {
                    AxisMarks(values: [0, avgPower, maxPower].sorted()) { value in
                        let val = value.as(Double.self) ?? 0
                        AxisValueLabel("\(Int(val))")
                    }
                }
                .chartXAxis {
                    AxisMarks(preset: .automatic, values: .stride(by: .hour)) { value in
                        if let time = value.as(Double.self) {
                            AxisValueLabel(timeFormatter(seconds: time))
                        }
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea.background(.clear)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Reusable Background Elevation Chart

struct ElevationBackgroundChart: View {
    let elevationData: [GraphableDataPoint]
    
    // Find the min/max for the Y-axis
    private var yDomain: ClosedRange<Double> {
        let values = elevationData.map { $0.value }
        let min = values.min() ?? 0
        let max = values.max() ?? 100
        // Add padding
        return (min * 0.9)...(max * 1.1)
    }
    
    var body: some View {
        Chart(elevationData) { dataPoint in
            AreaMark(
                x: .value("Time", dataPoint.time),
                y: .value("Elevation", dataPoint.value)
            )
            // Use a subtle gray fill like the screenshot
            .foregroundStyle(Color.gray.opacity(0.15))
            .interpolationMethod(.monotone)
        }
        .frame(height: 150)
        .chartYScale(domain: yDomain) // Use its own scale
        .chartYAxis(.hidden) // Hide its Y-axis
        .chartXAxis(.hidden) // Hide its X-axis
    }
}
