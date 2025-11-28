//
//  AIInsightsTab.swift
//  RideWeather Pro
//
//  Standalone tab for comprehensive AI weather-pacing insights
//

import SwiftUI

struct AIInsightsTab: View {
    @ObservedObject var viewModel: WeatherViewModel
    @State private var selectedCategory: InsightCategory = .all
    @State private var showingExportSheet = false
    
    enum InsightCategory: String, CaseIterable {
        case all = "All"
        case critical = "Critical"
        case pacing = "Pacing"
        case safety = "Safety"
        case weather = "Weather"
        
        var icon: String {
            switch self {
            case .all: return "sparkles"
            case .critical: return "exclamationmark.triangle.fill"
            case .pacing: return "speedometer"
            case .safety: return "shield.fill"
            case .weather: return "cloud.sun.fill"
            }
        }
    }
    
    private var insights: WeatherPacingInsightResult? {
        guard let powerAnalysis = viewModel.getPowerAnalysisResult(),
              let elevationAnalysis = viewModel.elevationAnalysis else { return nil }
        
        let aiEngine = AIWeatherPacingInsights(
            pacingPlan: viewModel.finalPacingPlan,
            powerAnalysis: powerAnalysis,
            weatherPoints: viewModel.weatherDataForRoute,
            settings: viewModel.settings,
            elevationAnalysis: elevationAnalysis
        )
        
        return aiEngine.generateInsights()
    }
    
    var body: some View {
        Group {
            if viewModel.weatherDataForRoute.isEmpty {
                emptyStateView
            } else if !viewModel.isPowerBasedAnalysisEnabled {
                powerDisabledView
            } else if let insights = insights {
                insightsContentView(insights)
            } else {
                noInsightsView
            }
        }
        .animatedBackground(
            gradient: .aiInsightsBackground,
            showDecoration: true,
            decorationColor: .white,
            decorationIntensity: 0.06
        )
        .sheet(isPresented: $showingExportSheet) {
            if let insights = insights {
                let exportData = generateExportText(for: insights)
                let filename = generateExportFilename()
                ShareSheetView(activityItems: [ExportItem(text: exportData, filename: filename)])
            }
        }
    }
    
    // MARK: - Content View
    
    private func insightsContentView(_ insights: WeatherPacingInsightResult) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                RouteInfoCardView(viewModel: viewModel)
                
                // AI Badge & Summary
                aiSummaryCard(insights)
                
                // Category Filter
                categoryFilterView
                
                // Filtered Content
                if selectedCategory == .all || selectedCategory == .critical {
                    if !insights.criticalSegments.isEmpty {
                        criticalSegmentsSection(insights.criticalSegments)
                    }
                }
                
                if selectedCategory == .all || selectedCategory != .critical {
                    filteredGuidanceSection(insights.strategicGuidance)
                }
                
                // Export Button
                exportButtonView
            }
            .padding()
        }
    }
    
    // MARK: - AI Summary Card
    
    private func aiSummaryCard(_ insights: WeatherPacingInsightResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Weather Intelligence")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("Physics-based analysis powered by real-time weather data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            if !insights.overallRecommendation.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("Overall Assessment", systemImage: "chart.bar.doc.horizontal")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(insights.overallRecommendation)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
            
            // Stats
            Divider()
            
            HStack(spacing: 20) {
                InsightStatView(
                    value: "\(insights.criticalSegments.count)",
                    label: "Critical\nSegments",
                    color: .red
                )
                
                InsightStatView(
                    value: "\(insights.strategicGuidance.count)",
                    label: "Strategic\nGuidances",
                    color: .blue
                )
                
                InsightStatView(
                    value: highImpactCount(insights),
                    label: "High\nImpact",
                    color: .orange
                )
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.15), Color.blue.opacity(0.05)],
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
    
    // MARK: - Category Filter
    
    private var categoryFilterView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(InsightCategory.allCases, id: \.self) { category in
                    CategoryChip(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Critical Segments Section
    
    private func criticalSegmentsSection(_ segments: [CriticalWeatherSegment]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Critical Weather Segments", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                
                Spacer()
                
                Text("\(segments.count)")
                    .font(.headline)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.red.opacity(0.15), in: Capsule())
            }
            
            ForEach(segments) { segment in
                CriticalWeatherSegmentRow(segment: segment)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Filtered Guidance Section
    
    private func filteredGuidanceSection(_ guidance: [StrategicGuidance]) -> some View {
        let filtered = filterGuidance(guidance)
        
        return Group {
            if !filtered.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(sectionTitle, systemImage: sectionIcon)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(sectionColor)
                        
                        Spacer()
                        
                        Text("\(filtered.count)")
                            .font(.headline)
                            .foregroundStyle(sectionColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(sectionColor.opacity(0.15), in: Capsule())
                    }
                    
                    ForEach(filtered) { item in
                        ExpandableStrategicGuidanceCard(guidance: item)
                    }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
    
    // MARK: - Export Button
    
    private var exportButtonView: some View {
        Button(action: {
            showingExportSheet = true
        }) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("Export AI Insights")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.blue)
            .foregroundStyle(.white)
            .cornerRadius(12)
            .font(.headline)
        }
        .padding(.horizontal)
        .disabled(insights == nil)
    }
    
    // MARK: - Empty States
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 64))
                .foregroundStyle(.gray.opacity(0.5))
            
            Text("No Route Imported")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Import a route to unlock AI-powered weather and pacing insights")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxHeight: .infinity)
    }
    
    private var powerDisabledView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 64))
                .foregroundStyle(.orange.opacity(0.5))
            
            Text("Power Analysis Disabled")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Enable power-based analysis in settings to access AI insights")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Enable Power Analysis") {
                viewModel.settings.speedCalculationMethod = .powerBased
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
    }
    
    private var noInsightsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(.blue.opacity(0.5))
            
            Text("No Significant Insights")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Weather conditions are favorable with no critical concerns detected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Text("✓ Good riding conditions")
                .font(.headline)
                .foregroundStyle(.green)
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Helper Methods
    
    private func generateExportFilename() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmm"
        let dateString = dateFormatter.string(from: Date())
        
        let routeName = viewModel.routeDisplayName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        
        return "\(routeName)-\(dateString)-insights.txt"
    }
    
    private func filterGuidance(_ guidance: [StrategicGuidance]) -> [StrategicGuidance] {
        switch selectedCategory {
        case .all:
            return guidance
        case .critical:
            return [] // Handled separately
        case .pacing:
            return guidance.filter { $0.category == .pacing || $0.category == .strategy }
        case .safety:
            return guidance.filter { $0.category == .safety }
        case .weather:
            return guidance.filter { $0.category == .nutrition || $0.category == .safety }
        }
    }
    
    private var sectionTitle: String {
        switch selectedCategory {
        case .all: return "Strategic Guidance"
        case .critical: return "" // Not used
        case .pacing: return "Pacing Strategy"
        case .safety: return "Safety Guidance"
        case .weather: return "Weather Strategy"
        }
    }
    
    private var sectionIcon: String {
        switch selectedCategory {
        case .all: return "lightbulb.fill"
        case .critical: return ""
        case .pacing: return "speedometer"
        case .safety: return "shield.fill"
        case .weather: return "cloud.sun.fill"
        }
    }
    
    private var sectionColor: Color {
        switch selectedCategory {
        case .all: return .blue
        case .critical: return .red
        case .pacing: return .green
        case .safety: return .orange
        case .weather: return .purple
        }
    }
    
    private func highImpactCount(_ insights: WeatherPacingInsightResult) -> String {
        let highCount = insights.strategicGuidance.filter {
            $0.impactLevel == .high || $0.impactLevel == .critical
        }.count
        let criticalSegments = insights.criticalSegments.filter { $0.severity >= 7 }.count
        return "\(highCount + criticalSegments)"
    }
    
    private func generateExportText(for insights: WeatherPacingInsightResult) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        
        var text = """
        ═══════════════════════════════════════════════
        AI WEATHER-PACING INSIGHTS
        Generated: \(formatter.string(from: Date()))
        ═══════════════════════════════════════════════
        
        Route: \(viewModel.routeDisplayName)
        Start Time: \(formatter.string(from: viewModel.rideDate))
        
        """
        
        if !insights.overallRecommendation.isEmpty {
            text += """
            
            📊 OVERALL ASSESSMENT
            ─────────────────────────────────────────────
            \(insights.overallRecommendation)
            
            """
        }
        
        if !insights.criticalSegments.isEmpty {
            text += """
            
            ⚠️  CRITICAL WEATHER SEGMENTS (\(insights.criticalSegments.count))
            ─────────────────────────────────────────────
            
            """
            
            for segment in insights.criticalSegments {
                text += """
                Segment \(segment.segmentIndex + 1) • \(segment.distanceMarker)
                Severity: \(Int(segment.severity))/10
                
                Conditions: \(segment.weatherConditions)
                
                """
                
                if !segment.powerAdjustment.isEmpty {
                    text += "⚡ Power: \(segment.powerAdjustment)\n"
                }
                
                if !segment.strategicNotes.isEmpty {
                    text += "💡 Strategy: \(segment.strategicNotes)\n"
                }
                
                text += "\n"
            }
        }
        
        if !insights.strategicGuidance.isEmpty {
            text += """
            
            💡 STRATEGIC GUIDANCE (\(insights.strategicGuidance.count))
            ─────────────────────────────────────────────
            
            """
            
            for guidance in insights.strategicGuidance {
                text += """
                \(guidance.title.uppercased())
                Impact: \(impactText(guidance.impactLevel))
                Category: \(categoryText(guidance.category))
                
                \(guidance.description)
                
                Action Items:
                
                """
                
                for item in guidance.actionItems {
                    text += "  • \(item)\n"
                }
                
                text += "\n"
            }
        }
        
        text += """
        
        ═══════════════════════════════════════════════
        Generated by RideWeather Pro AI
        ═══════════════════════════════════════════════
        """
        
        return text
    }
    
    private func impactText(_ level: StrategicGuidance.ImpactLevel) -> String {
        switch level {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "CRITICAL"
        }
    }
    
    private func categoryText(_ category: StrategicGuidance.GuidanceCategory) -> String {
        switch category {
        case .pacing: return "Pacing"
        case .strategy: return "Strategy"
        case .safety: return "Safety"
        case .nutrition: return "Nutrition"
        }
    }
}

// MARK: - Supporting Views

struct ExpandableStrategicGuidanceCard: View {
    let guidance: StrategicGuidance
    @State private var isExpanded = false
    
    var body: some View {
        StrategicGuidanceCard(
            guidance: guidance,
            isExpanded: isExpanded
        ) {
            withAnimation(.spring(response: 0.3)) {
                isExpanded.toggle()
            }
        }
    }
}

struct CategoryChip: View {
    let category: AIInsightsTab.InsightCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.caption)
                
                Text(category.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                isSelected ? Color.blue : Color(.secondarySystemGroupedBackground),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct InsightStatView: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(color)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Gradient Extension

extension LinearGradient {
    static var aiInsightsBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.1, green: 0.2, blue: 0.4),
                Color(red: 0.2, green: 0.1, blue: 0.3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Share Sheet

class ExportItem: NSObject, UIActivityItemSource {
    let text: String
    let filename: String
    
    init(text: String, filename: String) {
        self.text = text
        self.filename = filename
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return text
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return text
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return filename
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "public.plain-text"
    }
}

struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
