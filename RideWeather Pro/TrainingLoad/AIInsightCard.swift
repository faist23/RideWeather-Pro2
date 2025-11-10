//
//  AIInsightCard.swift
//  RideWeather Pro
//
//  UI component for displaying AI-generated insights
//


import SwiftUI

struct AIInsightCard: View {
    let insight: AIInsight
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: insight.priority.icon)
                    .font(.title3)
                    .foregroundColor(insight.priority.color)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(insight.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        // AI Badge
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                            Text("AI")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .cornerRadius(4)
                    }
                    
                    Text(insight.insight)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(isExpanded ? nil : 2)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding()
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    
                    // Explanation
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text("Why This Matters")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        
                        Text(insight.explanation)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal)
                    
                    // Recommendation
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                            Text("What To Do")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        
                        Text(insight.recommendation)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    
                    // Metadata
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(insight.generatedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: insight.confidence == "high" ? "checkmark.circle.fill" : "circle.dotted")
                                .font(.caption2)
                            Text("\(insight.confidence.capitalized) confidence")
                                .font(.caption2)
                        }
                        
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Loading State

struct AIInsightLoadingCard: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(.purple)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analyzing your data...")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("This may take a few seconds")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Debug/Settings View

struct AIInsightsDebugView: View {
    @ObservedObject var manager: AIInsightsManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    HStack {
                        Text("AI Insights")
                        Spacer()
                        Text(AIInsightsManager.isEnabled ? "Enabled" : "Disabled")
                            .foregroundColor(AIInsightsManager.isEnabled ? .green : .gray)
                    }
                    
                    if let lastAnalysis = manager.lastAnalysisDate {
                        HStack {
                            Text("Last Analysis")
                            Spacer()
                            Text(lastAnalysis.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Usage Stats") {
                    HStack {
                        Text("Total Requests")
                        Spacer()
                        Text("\(manager.requestCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Total Cost")
                        Spacer()
                        Text("$\(String(format: "%.4f", manager.totalCost))")
                            .foregroundColor(.secondary)
                    }
                    
                    if manager.requestCount > 0 {
                        HStack {
                            Text("Avg Cost/Request")
                            Spacer()
                            Text("$\(String(format: "%.4f", manager.totalCost / Double(manager.requestCount)))")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Actions") {
                    Button(role: .destructive) {
                        manager.clearInsight()
                    } label: {
                        Text("Clear Current Insight")
                    }
                    
                    Button(role: .destructive) {
                        manager.resetUsageStats()
                    } label: {
                        Text("Reset Usage Stats")
                    }
                }
                
                Section {
                    Text("AI insights are generated automatically when there's a meaningful pattern or anomaly in your training data. The system checks your metrics and only calls the API when there's something actionable to report.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("AI Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        AIInsightCard(insight: AIInsight(
            priority: .warning,
            title: "Recovery Mismatch Detected",
            insight: "Your training load shows you're recovered, but physiological metrics suggest otherwise.",
            explanation: "Your TSB is positive (+8), indicating mathematical recovery. However, your HRV is 28% below baseline and resting heart rate is elevated by 6bpm. This disconnect suggests your nervous system hasn't recovered despite reduced training volume.",
            recommendation: "Replace today's planned interval session with an easy 60-minute spin at <65% FTP. Prioritize 8+ hours of sleep tonight. Reassess metrics tomorrow morning before any hard efforts.",
            confidence: "high",
            generatedAt: Date()
        ))
        
        AIInsightLoadingCard()
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
