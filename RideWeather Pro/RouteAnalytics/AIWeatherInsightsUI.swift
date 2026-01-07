//
//  AIWeatherInsightsUI.swift
//  RideWeather Pro
//
//  UI Components for AI Weather-Pacing Insights
//

import SwiftUI

/*// MARK: - Compact Card for Dashboard

struct AIInsightsCompactCard: View {
    let insights: WeatherPacingInsightResult
    @ObservedObject var viewModel: WeatherViewModel
    @State private var showingFullInsights = false
    
    var body: some View {
        Button(action: {
            showingFullInsights = true
        }) {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    
                    Text("AI Weather Intelligence")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Text("View Details")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                
                // Quick Stats
                HStack(spacing: 16) {
                    CompactStatBadge(
                        value: "\(insights.criticalSegments.count)",
                        label: "Critical",
                        color: .red
                    )
                    
                    CompactStatBadge(
                        value: "\(highImpactCount)",
                        label: "High Impact",
                        color: .orange
                    )
                    
                    CompactStatBadge(
                        value: "\(insights.strategicGuidance.count)",
                        label: "Guidance",
                        color: .blue
                    )
                }
                
                // Top Insight Preview
                if let topSegment = insights.criticalSegments.first {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle()
                                .fill(topSegment.severityColor)
                                .frame(width: 8, height: 8)
                            
                            Text("Most Critical: Segment \(topSegment.segmentIndex + 1)")
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            Spacer()
                        }
                        
                        Text(topSegment.weatherConditions)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: [Color.blue.opacity(0.12), Color.blue.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingFullInsights) {
            NavigationStack {
                AIInsightsTab(viewModel: viewModel)
                    .navigationTitle("AI Insights")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showingFullInsights = false
                            }
                        }
                    }
            }
        }
    }
    
    private var highImpactCount: Int {
        insights.strategicGuidance.filter {
            $0.impactLevel == .high || $0.impactLevel == .critical
        }.count + insights.criticalSegments.filter { $0.severity >= 7 }.count
    }
}*/

struct CompactStatBadge: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Main Insights Card

struct AIWeatherPacingInsightsCard: View {
    let insights: WeatherPacingInsightResult
    @State private var expandedGuidanceId: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with AI badge
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                    .font(.title3)
                
                Text("AI Weather-Pacing Insights")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Image(systemName: "wind")
                    .foregroundStyle(.blue.opacity(0.6))
            }
            
            // Overall Recommendation
            if !insights.overallRecommendation.isEmpty {
                Text(insights.overallRecommendation)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.15), Color.blue.opacity(0.05)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            }
            
            // Critical Segments
            if !insights.criticalSegments.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Critical Weather Segments", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                    
                    ForEach(insights.criticalSegments.prefix(5)) { segment in
                        CriticalWeatherSegmentRow(segment: segment)
                    }
                    
                    if insights.criticalSegments.count > 5 {
                        Text("+ \(insights.criticalSegments.count - 5) more critical segments")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
            
            // Strategic Guidance
            if !insights.strategicGuidance.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Strategic Recommendations", systemImage: "lightbulb.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.yellow)
                    
                    ForEach(insights.strategicGuidance) { guidance in
                        StrategicGuidanceCard(
                            guidance: guidance,
                            isExpanded: expandedGuidanceId == guidance.id
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                expandedGuidanceId = expandedGuidanceId == guidance.id ? nil : guidance.id
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Critical Weather Segment Row

struct CriticalWeatherSegmentRow: View {
    let segment: CriticalWeatherSegment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with severity indicator
            HStack {
                Circle()
                    .fill(segment.severityColor)
                    .frame(width: 8, height: 8)
                
                Text("Segment \(segment.segmentIndex + 1)")
                    .font(.caption)
                    .fontWeight(.bold)
                
                Text(segment.distanceMarker)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("Severity: \(Int(segment.severity))")
                    .font(.caption2)
                    .foregroundStyle(segment.severityColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(segment.severityColor.opacity(0.2), in: Capsule())
            }
            
            // Weather Conditions
            if !segment.weatherConditions.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "cloud.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    
                    Text(segment.weatherConditions)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
            
            // Power Adjustment
            if !segment.powerAdjustment.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(width: 16)
                    
                    Text(segment.powerAdjustment)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                }
            }
            
            // Strategic Notes
            if !segment.strategicNotes.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .frame(width: 16)
                    
                    Text(segment.strategicNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(segment.severityColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(segment.severityColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Strategic Guidance Card

struct StrategicGuidanceCard: View {
    let guidance: StrategicGuidance
    let isExpanded: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: guidance.category.icon)
                        .font(.title3)
                        .foregroundStyle(guidance.impactLevel.color)
                        .frame(width: 28)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guidance.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        HStack {
                            Text(impactLevelText)
                                .font(.caption2)
                                .foregroundStyle(guidance.impactLevel.color)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            Text(categoryText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Expanded Content
                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        Divider()
                        
                        // Description
                        Text(guidance.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        // Action Items with icons
                        if !guidance.actionItems.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(guidance.impactLevel.color)
                                    Text("Action Items:")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                }
                                
                                ForEach(guidance.actionItems.indices, id: \.self) { index in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(index + 1).")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundStyle(guidance.impactLevel.color)
                                            .frame(width: 20, alignment: .trailing)
                                        
                                        Text(guidance.actionItems[index])
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(guidance.impactLevel.color.opacity(0.08))
                            )
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }
            .padding(14)
            .background(
                guidance.impactLevel.color.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(guidance.impactLevel.color.opacity(0.3), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var impactLevelText: String {
        switch guidance.impactLevel {
        case .low: return "Low Impact"
        case .medium: return "Medium Impact"
        case .high: return "High Impact"
        case .critical: return "Critical"
        }
    }
    
    private var categoryText: String {
        switch guidance.category {
        case .pacing: return "Pacing"
        case .strategy: return "Strategy"
        case .safety: return "Safety"
        case .nutrition: return "Nutrition"
        }
    }
}

/*// MARK: - Preview Helper

#if DEBUG
struct AIWeatherInsightsUI_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 20) {
                AIWeatherPacingInsightsCard(insights: sampleInsights)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
    
    static var sampleInsights: WeatherPacingInsightResult {
        WeatherPacingInsightResult(
            criticalSegments: [
                CriticalWeatherSegment(
                    segmentIndex: 15,
                    distanceMarker: "18.5 mi",
                    weatherConditions: "Strong 18mph headwind",
                    powerAdjustment: "Add 85W above plan",
                    strategicNotes: "⚠️ CRITICAL: This is a time-savings segment - push harder here",
                    severity: 9.0
                ),
                CriticalWeatherSegment(
                    segmentIndex: 23,
                    distanceMarker: "25.2 mi",
                    weatherConditions: "Moderate 12mph headwind • 5% climb",
                    powerAdjustment: "Add 60W to maintain pace",
                    strategicNotes: "Headwind + climb combination = maximum difficulty",
                    severity: 8.0
                )
            ],
            strategicGuidance: [
                StrategicGuidance(
                    category: .pacing,
                    title: "Headwind Power Strategy",
                    description: "You'll face 45 minutes of significant headwind (18mph). Research shows pushing 10-15% harder into headwinds reduces overall time more than conserving energy.",
                    actionItems: [
                        "Target +60W during strong headwind segments",
                        "This will feel hard but saves time where it counts most",
                        "Plan to recover during tailwind/descent sections"
                    ],
                    impactLevel: .high
                )
            ],
            overallRecommendation: "⚠️ HEADWIND-DOMINATED ROUTE (62% of ride time at 16mph average). Strategy: Push 10-15% harder into wind, recover with tailwind. Expected time impact: +8 minutes vs. calm conditions."
        )
    }
}
#endif
*/
