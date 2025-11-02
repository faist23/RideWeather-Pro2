//
//  TrainingLoadExplanationView.swift
//  RideWeather Pro
//
//  Explains training load concepts to users
//

import SwiftUI

struct TrainingLoadExplanationView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Understanding Training Load")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Track your fitness, fatigue, and form to optimize training and avoid overtraining.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // CTL
                    MetricExplanation(
                        title: "Fitness (CTL)",
                        subtitle: "Chronic Training Load",
                        color: .blue,
                        icon: "figure.strengthtraining.traditional",
                        description: "Your long-term training load, averaged over 42 days. This represents your overall fitness level.",
                        interpretation: [
                            "CTL 0-40: Beginner fitness",
                            "CTL 40-80: Intermediate fitness",
                            "CTL 80-120: Advanced fitness",
                            "CTL 120+: Elite fitness"
                        ]
                    )
                    
                    // ATL
                    MetricExplanation(
                        title: "Fatigue (ATL)",
                        subtitle: "Acute Training Load",
                        color: .orange,
                        icon: "battery.25",
                        description: "Your recent training load, averaged over 7 days. This represents how fatigued you are right now.",
                        interpretation: [
                            "ATL > CTL: Building fatigue quickly",
                            "ATL = CTL: Balanced training",
                            "ATL < CTL: Recovering or tapering"
                        ]
                    )
                    
                    // TSB
                    MetricExplanation(
                        title: "Form (TSB)",
                        subtitle: "Training Stress Balance",
                        color: .green,
                        icon: "heart.fill",
                        description: "Calculated as CTL - ATL. Shows whether you're fresh or fatigued. The key metric for race readiness.",
                        interpretation: [
                            "TSB < -30: Very fatigued, high injury risk",
                            "TSB -30 to -10: Fatigued, need recovery soon",
                            "TSB -10 to +5: Optimal for training",
                            "TSB +5 to +15: Fresh, good for racing",
                            "TSB > +15: Very fresh (or detraining)"
                        ]
                    )
                    
                    Divider()
                    
                    // TSS
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.yellow)
                                .font(.title2)
                            Text("Training Stress Score (TSS)")
                                .font(.headline)
                        }
                        
                        Text("TSS quantifies how hard a workout was, accounting for both intensity and duration.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reference values:")
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            ForEach([
                                "1 hour at FTP = 100 TSS",
                                "Easy 2-hour ride = 100-120 TSS",
                                "Hard 90min ride = 130-150 TSS",
                                "Century ride = 300-400 TSS"
                            ], id: \.self) { item in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.yellow)
                                        .frame(width: 6, height: 6)
                                    Text(item)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    
                    Divider()
                    
                    // Ramp Rate
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.blue)
                                .font(.title2)
                            Text("Ramp Rate")
                                .font(.headline)
                        }
                        
                        Text("How fast your fitness (CTL) is changing per week.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            RampRateItem(range: "+5 to +8 TSS/week", status: "Optimal building", color: .green)
                            RampRateItem(range: "+3 to +5 TSS/week", status: "Safe building", color: .blue)
                            RampRateItem(range: "-3 to +3 TSS/week", status: "Maintaining", color: .gray)
                            RampRateItem(range: "> +8 TSS/week", status: "Too fast - injury risk", color: .orange)
                            RampRateItem(range: "< -8 TSS/week", status: "Detraining", color: .red)
                        }
                    }
                    
                    Divider()
                    
                    // Practical Tips
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                                .font(.title2)
                            Text("Practical Tips")
                                .font(.headline)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            TipItem(tip: "Increase CTL by 5-8 TSS per week for sustainable gains")
                            TipItem(tip: "Peak for events with TSB between +5 and +15")
                            TipItem(tip: "Take a recovery week when TSB drops below -20")
                            TipItem(tip: "Allow 1 day of recovery per 100 TSS of training")
                            TipItem(tip: "Build CTL in base phase, manage TSB for races")
                        }
                    }
                }
                .padding()
            }
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

struct MetricExplanation: View {
    let title: String
    let subtitle: String
    let color: Color
    let icon: String
    let description: String
    let interpretation: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(interpretation, id: \.self) { item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                        Text(item)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

struct RampRateItem: View {
    let range: String
    let status: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(range)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(width: 120, alignment: .leading)
            
            Text(status)
                .font(.caption)
                .foregroundColor(color)
        }
        .padding(.vertical, 4)
    }
}

struct TipItem: View {
    let tip: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
            
            Text(tip)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
