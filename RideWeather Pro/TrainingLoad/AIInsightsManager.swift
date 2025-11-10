//
//  AIInsightsManager.swift
//  RideWeather Pro
//
//  AI-powered training insights using Claude API
//  Easy to disable/remove: Just set isEnabled = false
//


import Foundation
import SwiftUI
import Combine

@MainActor
class AIInsightsManager: ObservableObject {
    
    // MARK: - Configuration
    private var anthropicConfig: [String: String]?

    private var apiKey: String {
        let key = configValue(forKey: "AIKey") ?? "INVALID_API"
        
        if key == "INVALID_API" {
            print("🤖 AI Insights: ❌ No valid API key found")
        } else {
            print("🤖 AI Insights: ✅ API key loaded: \(key.prefix(15))...")
        }
        
        return key
    }
    
    private func configValue(forKey key: String) -> String? {
        return anthropicConfig?[key]
    }

    // MARK: - Kill Switch
    /// Set this to false to completely disable AI insights without removing code
    static let isEnabled = true
    
    // MARK: - Published Properties
    @Published var currentInsight: AIInsight?
    @Published var isLoading = false
    @Published var lastAnalysisDate: Date?
    @Published var totalCost: Double = 0.0  // Track spending
    @Published var requestCount: Int = 0
    
    // MARK: - Usage Tracking
    private let costPerInputToken = 0.000003  // $3 per 1M tokens
    private let costPerOutputToken = 0.000015 // $15 per 1M tokens
    
    private let userDefaults = UserDefaults.standard
    private let insightKey = "cachedAIInsight"
    private let costKey = "totalAICost"
    private let requestCountKey = "aiRequestCount"
    
    init() {
        loadConfig() // Load the plist first
        loadCachedData()
    }

    private func loadConfig() {
         // Check if file exists
        guard let path = Bundle.main.path(forResource: "AnthropicConfig", ofType: "plist") else {
            print("🤖 AI Insights: ❌ AnthropicConfig.plist not found in bundle")
            print("🤖 AI Insights: 📁 Bundle path: \(Bundle.main.bundlePath)")
            anthropicConfig = [:]
            return
        }
         // Try to load as NSDictionary
        guard let config = NSDictionary(contentsOfFile: path) as? [String: String] else {
            print("🤖 AI Insights: ❌ Failed to parse plist as [String: String]")
            
            // Try to see what's actually in the file
            if let rawDict = NSDictionary(contentsOfFile: path) {
 //               print("🤖 AI Insights: 📋 Raw plist contents: \(rawDict)")
            }
            
            anthropicConfig = [:]
            return
        }
        
        self.anthropicConfig = config
 //       print("🤖 AI Insights: ✅ Loaded config: \(config)")
 //       print("🤖 AI Insights: 🔑 Keys in plist: \(config.keys)")
    }
    
    // MARK: - Public Methods
    
    /// Generate AI insight when there's a meaningful pattern or anomaly
    func analyzeIfNeeded(
        summary: TrainingLoadSummary?,
        readiness: PhysiologicalReadiness?,
        recentLoads: [DailyTrainingLoad]
    ) async {
        guard Self.isEnabled else {
            print("🤖 AI Insights: Disabled")
            return
        }
        
        // Only analyze if there's something interesting
        guard shouldAnalyze(summary: summary, readiness: readiness) else {
            print("🤖 AI Insights: No analysis needed - metrics look normal")
            return
        }
        
        // Rate limiting: Don't analyze more than once per 6 hours
        if let lastAnalysis = lastAnalysisDate,
           Date().timeIntervalSince(lastAnalysis) < 6 * 3600 {
            print("🤖 AI Insights: Too soon since last analysis")
            return
        }
        
        await generateInsight(summary: summary, readiness: readiness, recentLoads: recentLoads)
    }
    
    /// Force generate an insight (for user-initiated "Analyze Now" button)
    func forceAnalyze(
        summary: TrainingLoadSummary?,
        readiness: PhysiologicalReadiness?,
        recentLoads: [DailyTrainingLoad]
    ) async {
        guard Self.isEnabled else { return }
        await generateInsight(summary: summary, readiness: readiness, recentLoads: recentLoads)
    }
    
    /// Clear cached insight
    func clearInsight() {
        currentInsight = nil
        userDefaults.removeObject(forKey: insightKey)
    }
    
    /// Reset all usage tracking
    func resetUsageStats() {
        totalCost = 0.0
        requestCount = 0
        userDefaults.removeObject(forKey: costKey)
        userDefaults.removeObject(forKey: requestCountKey)
    }
    
    // MARK: - Private Methods
    
    private func shouldAnalyze(summary: TrainingLoadSummary?, readiness: PhysiologicalReadiness?) -> Bool {
        // Analyze if there's a TSB/readiness mismatch
        if let summary = summary, let readiness = readiness {
            let hrvIsLow = (readiness.latestHRV ?? 50) < ((readiness.averageHRV ?? 50) * 0.85)
            let rhrIsHigh = (readiness.latestRHR ?? 60) > ((readiness.averageRHR ?? 60) + 4)
            
            if summary.currentTSB > 5 && (hrvIsLow || rhrIsHigh) {
                return true // Mismatch detected
            }
        }
        
        // Analyze if TSB is critically low
        if let summary = summary, summary.currentTSB < -20 {
            return true
        }
        
        // Analyze if ramp rate is dangerous
        if let summary = summary, abs(summary.rampRate) > 8 {
            return true
        }
        
        return false
    }
    
    private func generateInsight(
        summary: TrainingLoadSummary?,
        readiness: PhysiologicalReadiness?,
        recentLoads: [DailyTrainingLoad]
    ) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let prompt = buildPrompt(summary: summary, readiness: readiness, recentLoads: recentLoads)
            
            let response = try await callClaudeAPI(prompt: prompt)
            
            // Parse the response
            if let insight = parseInsightResponse(response) {
                currentInsight = insight
                lastAnalysisDate = Date()
                cacheInsight(insight)
                print("🤖 AI Insights: Generated new insight")
            }
            
        } catch {
            print("🤖 AI Insights Error: \(error.localizedDescription)")
        }
    }
    
    private func buildPrompt(
        summary: TrainingLoadSummary?,
        readiness: PhysiologicalReadiness?,
        recentLoads: [DailyTrainingLoad]
    ) -> String {
        var prompt = """
        You are an expert cycling coach analyzing training data for actionable insights.
        
        CRITICAL: Your response must be a single JSON object with this exact structure:
        {
          "priority": "critical" | "warning" | "info",
          "title": "Brief title (max 50 chars)",
          "insight": "Main insight (2-3 sentences, max 200 chars)",
          "explanation": "Why this matters (2-3 sentences, max 250 chars)",
          "recommendation": "Specific action to take (1-2 sentences, max 200 chars)",
          "confidence": "high" | "moderate" | "low"
        }
        
        Current Training Load:
        """
        
        if let summary = summary {
            prompt += """
            
            - Fitness (CTL): \(String(format: "%.1f", summary.currentCTL))
            - Fatigue (ATL): \(String(format: "%.1f", summary.currentATL))
            - Form (TSB): \(String(format: "%.1f", summary.currentTSB))
            - Ramp Rate: \(String(format: "%.1f", summary.rampRate)) TSS/week
            - Weekly TSS: \(String(format: "%.0f", summary.weeklyTSS))
            """
        }
        
        if let readiness = readiness {
            prompt += """
            
            
            Current Physiological Metrics:
            """
            
            if let hrv = readiness.latestHRV, let avgHRV = readiness.averageHRV {
                let hrvChange = ((hrv - avgHRV) / avgHRV) * 100
                prompt += "\n- HRV: \(Int(hrv))ms (7d avg: \(Int(avgHRV))ms, \(String(format: "%+.1f", hrvChange))%)"
            }
            
            if let rhr = readiness.latestRHR, let avgRHR = readiness.averageRHR {
                let rhrChange = rhr - avgRHR
                prompt += "\n- Resting HR: \(Int(rhr))bpm (7d avg: \(Int(avgRHR))bpm, \(String(format: "%+.1f", rhrChange))bpm)"
            }
            
            if let sleep = readiness.sleepDuration {
                let hours = Int(sleep) / 3600
                let minutes = (Int(sleep) % 3600) / 60
                prompt += "\n- Last night's sleep: \(hours)h \(minutes)m"
                
                if let avgSleep = readiness.averageSleepDuration {
                    let avgHours = Int(avgSleep) / 3600
                    let avgMinutes = (Int(avgSleep) % 3600) / 60
                    prompt += " (7d avg: \(avgHours)h \(avgMinutes)m)"
                }
            }
        }
        
        // Add recent 7 days of training
        let recent = recentLoads.prefix(7)
        if !recent.isEmpty {
            prompt += """
            
            
            Last 7 Days Training:
            """
            for load in recent {
                let dateStr = load.date.formatted(date: .abbreviated, time: .omitted)
                prompt += "\n- \(dateStr): \(String(format: "%.0f", load.tss)) TSS"
            }
        }
        
        prompt += """
        
        
        Analyze this data and provide ONE specific, actionable insight.
        Focus on:
        1. Conflicts between training load math and physiological signals
        2. Patterns that suggest injury risk or overtraining
        3. Opportunities for optimal training timing
        
        Be concise, specific, and actionable. Respond ONLY with the JSON object, no other text.
        """
        
        return prompt
    }
    
    private func callClaudeAPI(prompt: String) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIInsightError.networkError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(self.apiKey, forHTTPHeaderField: "x-api-key")
        
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1000,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
       
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIInsightError.networkError
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AIInsightError.apiError(message)
            }
            throw AIInsightError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]],
              let firstContent = contentArray.first,
              let text = firstContent["text"] as? String else {
            throw AIInsightError.invalidResponse
        }
        
        // Track usage
        if let usage = json["usage"] as? [String: Int] {
            let inputTokens = usage["input_tokens"] ?? 0
            let outputTokens = usage["output_tokens"] ?? 0
            
            let cost = Double(inputTokens) * costPerInputToken + Double(outputTokens) * costPerOutputToken
            totalCost += cost
            requestCount += 1
            
            userDefaults.set(totalCost, forKey: costKey)
            userDefaults.set(requestCount, forKey: requestCountKey)
            
            print("🤖 AI Insights: Request cost $\(String(format: "%.4f", cost)) (Total: $\(String(format: "%.2f", totalCost)), \(requestCount) requests)")
        }
        
        return text
    }
    
    private func parseInsightResponse(_ response: String) -> AIInsight? {
        // Remove any markdown formatting if present
        let cleanedResponse = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanedResponse.data(using: .utf8),
              let json = try? JSONDecoder().decode(AIInsightResponse.self, from: data) else {
            print("🤖 AI Insights: Failed to parse response")
            return nil
        }
        
        return AIInsight(
            priority: AIInsight.Priority(rawValue: json.priority) ?? .info,
            title: json.title,
            insight: json.insight,
            explanation: json.explanation,
            recommendation: json.recommendation,
            confidence: json.confidence,
            generatedAt: Date()
        )
    }
    
    // MARK: - Caching
    
    private func cacheInsight(_ insight: AIInsight) {
        if let encoded = try? JSONEncoder().encode(insight) {
            userDefaults.set(encoded, forKey: insightKey)
        }
    }
    
    private func loadCachedData() {
        // Load cached insight
        if let data = userDefaults.data(forKey: insightKey),
           let insight = try? JSONDecoder().decode(AIInsight.self, from: data) {
            // Only use if less than 24 hours old
            if Date().timeIntervalSince(insight.generatedAt) < 24 * 3600 {
                currentInsight = insight
                lastAnalysisDate = insight.generatedAt
            }
        }
        
        // Load usage stats
        totalCost = userDefaults.double(forKey: costKey)
        requestCount = userDefaults.integer(forKey: requestCountKey)
    }
}

// MARK: - Models

struct AIInsight: Codable, Identifiable {
    let id: UUID
    let priority: Priority
    let title: String
    let insight: String
    let explanation: String
    let recommendation: String
    let confidence: String
    let generatedAt: Date
    
    init(id: UUID = UUID(), priority: Priority, title: String, insight: String, explanation: String, recommendation: String, confidence: String, generatedAt: Date) {
        self.id = id
        self.priority = priority
        self.title = title
        self.insight = insight
        self.explanation = explanation
        self.recommendation = recommendation
        self.confidence = confidence
        self.generatedAt = generatedAt
    }
    
    enum Priority: String, Codable {
        case critical, warning, info
        
        var color: Color {
            switch self {
            case .critical: return .red
            case .warning: return .orange
            case .info: return .purple
            }
        }
        
        var icon: String {
            switch self {
            case .critical: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .info: return "brain.head.profile"
            }
        }
    }
}

private struct AIInsightResponse: Codable {
    let priority: String
    let title: String
    let insight: String
    let explanation: String
    let recommendation: String
    let confidence: String
}

enum AIInsightError: Error {
    case invalidResponse
    case networkError
    case apiError(String)
    
    var localizedDescription: String {
        switch self {
        case .invalidResponse:
            return "Invalid API response"
        case .networkError:
            return "Network error"
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}
