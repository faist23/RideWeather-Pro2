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
              let elevationAnalysis = viewModel.elevationAnalysis,
              viewModel.finalPacingPlan != nil else { return nil }
        
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
            } else if viewModel.finalPacingPlan == nil {
                noPacingPlanView
            } else if let insights = insights, hasActionableInsights(insights) {
                insightsContentView(insights)
            } else {
                noActionableInsightsView
            }
        }
        .animatedBackground(
            gradient: .aiInsightsBackground,
            showDecoration: true,
            decorationColor: .white,
            decorationIntensity: 0.06
        )
        .sheet(isPresented: $showingExportSheet) {
            Group {
                if let insights = insights {
                    let exportData = generateExportText(for: insights)
                    let filename = generateExportFilename()
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                    // Return a ShareSheetView and write the file as a side effect when presented
                    ShareSheetView(activityItems: [tempURL])
                        .task {
                            try? exportData.write(to: tempURL, atomically: true, encoding: .utf8)
                        }
                } else {
                    // Fallback to an empty view if insights are missing
                    EmptyView()
                }
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
                    Text("AI Strategic Intelligence")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("Non-obvious insights you might miss")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            if !insights.overallRecommendation.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("Key Strategic Insight", systemImage: "lightbulb.fill")
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
                    label: "Strategic\nInsights",
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
            
            Text("Import a route to unlock AI-powered strategic insights")
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
    
    private var noActionableInsightsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 64))
                .foregroundStyle(.green.opacity(0.5))
            
            Text("No Strategic Insights Needed")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Conditions are straightforward with no critical tactical opportunities or concerns")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Text("✓ Ride as planned")
                .font(.headline)
                .foregroundStyle(.green)
        }
        .frame(maxHeight: .infinity)
    }
    
    private var noPacingPlanView: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 64))
                .foregroundStyle(.blue.opacity(0.5))
            
            Text("Pacing Plan Required")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("AI insights analyze your pacing plan's power distribution and strategic opportunities")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Text("Generate a pacing plan first to see AI-powered strategic insights")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Helper Methods
    
    private func hasActionableInsights(_ insights: WeatherPacingInsightResult) -> Bool {
        // Only show tab if there are truly actionable insights
        return !insights.criticalSegments.isEmpty || !insights.strategicGuidance.isEmpty
    }
    
    private func generateExportFilename() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmm"
        let dateString = dateFormatter.string(from: Date())
        
        // Use the viewModel's helper method to generate proper filename
        return viewModel.generateExportFilename(
            baseName: nil, // Let it use the stored route name
            suffix: "\(dateString)-ai",
            extension: "txt"
        )
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
        AI STRATEGIC INTELLIGENCE
        Generated: \(formatter.string(from: Date()))
        ═══════════════════════════════════════════════
        
        Route: \(viewModel.routeDisplayName)
        Start Time: \(formatter.string(from: viewModel.rideDate))
        
        """
        
        if !insights.overallRecommendation.isEmpty {
            text += """
            
            💡 KEY STRATEGIC INSIGHT
            ─────────────────────────────────────────────
            \(insights.overallRecommendation)
            
            """
        }
        
        if !insights.criticalSegments.isEmpty {
            text += """
            
            ⚠️  CRITICAL TACTICAL OPPORTUNITIES (\(insights.criticalSegments.count))
            ─────────────────────────────────────────────
            
            """
            
            for segment in insights.criticalSegments {
                text += """
                📍 \(segment.distanceMarker)
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
            
            🎯 STRATEGIC GUIDANCE (\(insights.strategicGuidance.count))
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
