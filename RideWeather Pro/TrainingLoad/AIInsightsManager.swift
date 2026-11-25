//
//  AIInsightsManager.swift
//  RideWeather Pro
//
//  AI-powered training insights via a direct Anthropic Messages API call.
//  The key is read from AnthropicConfig.plist (gitignored, key `AIKey`).
//  Easy to disable/remove: Just set isEnabled = false
//


import Foundation
import SwiftUI
import Combine

@MainActor
class AIInsightsManager: ObservableObject {

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
    private let costPerInputToken = 0.000002  // $2 per 1M tokens (Sonnet 5.5)
    private let costPerOutputToken = 0.000010 // $10 per 1M tokens (Sonnet 5.5)
    
    private let userDefaults = UserDefaults.standard
    private let insightKey = "cachedAIInsight"
    private let costKey = "totalAICost"
    private let requestCountKey = "aiRequestCount"
    /// Fingerprint of the recent training the cached insight was built from.
    private let trainingFingerprintKey = "aiInsightTrainingFingerprint"

    // MARK: - Configuration
    private static let messagesEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-sonnet-5-5"
    /// Server-side refusal fallback (opt-in beta): a `cyber`/`frontier_llm`
    /// decline is re-run on Claude Sonnet 5 inside the same call.
    private static let fallbackBeta = "server-side-fallback-2026-07-01"

    /// JSON Schema for the insight; enforced by structured outputs so the
    /// reply is always a decodable `AIInsightResponse`.
    private static let insightSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "priority": ["type": "string", "enum": ["critical", "warning", "info"]],
            "title": ["type": "string"],
            "insight": ["type": "string"],
            "explanation": ["type": "string"],
            "recommendation": ["type": "string"],
            "confidence": ["type": "string", "enum": ["high", "moderate", "low"]]
        ],
        "required": ["priority", "title", "insight", "explanation", "recommendation", "confidence"],
        "additionalProperties": false
    ]

    private var anthropicConfig: [String: String]?

    private var apiKey: String? {
        guard let key = anthropicConfig?["AIKey"], !key.isEmpty else { return nil }
        return key
    }

    init() {
        loadConfig()
        loadCachedData()
    }

    /// Loads the Anthropic key from AnthropicConfig.plist. The plist is
    /// gitignored like the other config plists, so a fresh checkout has to
    /// recreate it before insights will work.
    private func loadConfig() {
        guard let path = Bundle.main.path(forResource: "AnthropicConfig", ofType: "plist") else {
            print("🤖 AI Insights: ❌ AnthropicConfig.plist not found in bundle")
            anthropicConfig = [:]
            return
        }

        guard let config = NSDictionary(contentsOfFile: path) as? [String: String] else {
            print("🤖 AI Insights: ❌ Failed to parse AnthropicConfig.plist as [String: String]")
            anthropicConfig = [:]
            return
        }

        anthropicConfig = config
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
           Date().timeIntervalSince(lastAnalysis) < 6 * 3600,
           !trainingChangedSinceLastInsight(recentLoads) {
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
        
        // ADDED: Analyze if weekly TSS is very high
        if let summary = summary, summary.weeklyTSS > 500 {
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

            let insight = try await fetchInsight(prompt: prompt)
            currentInsight = insight
            lastAnalysisDate = Date()
            cacheInsight(insight)
            userDefaults.set(Self.trainingFingerprint(recentLoads), forKey: trainingFingerprintKey)
            print("🤖 AI Insights: Generated new insight")

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
        
        prompt += Self.recentTrainingSection(from: recentLoads)
        
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
    
    /// Requests an insight straight from the Anthropic Messages API.
    ///
    /// Thinking is turned off with `between_tools` (Sonnet 5.5 rejects
    /// `disabled`): left adaptive, thinking would eat the small `max_tokens`
    /// budget before the JSON is written. Structured outputs guarantee the
    /// JSON shape; refusals and truncation are reported as distinct errors.
    private func fetchInsight(prompt: String) async throws -> AIInsight {
        guard let apiKey else {
            throw AIInsightError.missingAPIKey
        }

        var request = URLRequest(url: Self.messagesEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 1024,
            "thinking": ["type": "between_tools"],
            "output_config": [
                "effort": "high",
                "format": ["type": "json_schema", "schema": Self.insightSchema]
            ],
            "fallbacks": "default",
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIInsightError.apiError("No HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            throw AIInsightError.apiError(message ?? "HTTP \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIInsightError.invalidResponse
        }

        // Bill tracking first: refused and truncated replies are still charged.
        if let usage = json["usage"] as? [String: Any] {
            trackUsage(
                inputTokens: usage["input_tokens"] as? Int ?? 0,
                outputTokens: usage["output_tokens"] as? Int ?? 0
            )
        }

        // Check why generation stopped before reading content: a refusal or a
        // max_tokens cut-off can leave text that doesn't match the schema.
        switch json["stop_reason"] as? String {
        case "refusal":
            throw AIInsightError.refused
        case "max_tokens":
            throw AIInsightError.truncated
        default:
            break
        }

        guard let content = json["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        else {
            throw AIInsightError.invalidResponse
        }

        let insight = try decodeInsightPayload(from: text)
        return AIInsight(
            priority: AIInsight.Priority(rawValue: insight.priority) ?? .info,
            title: insight.title,
            insight: insight.insight,
            explanation: insight.explanation,
            recommendation: insight.recommendation,
            confidence: insight.confidence,
            generatedAt: Date()
        )
    }

    /// Structured outputs make the reply a bare JSON object; trimming to the
    /// outermost braces stays as a guard for a reply served by a fallback.
    private func decodeInsightPayload(from text: String) throws -> AIInsightResponse {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end
        else {
            throw AIInsightError.invalidResponse
        }

        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(AIInsightResponse.self, from: data)
        else {
            throw AIInsightError.invalidResponse
        }

        return payload
    }

    private func trackUsage(inputTokens: Int, outputTokens: Int) {
        let cost = Double(inputTokens) * costPerInputToken + Double(outputTokens) * costPerOutputToken
        totalCost += cost
        requestCount += 1

        userDefaults.set(totalCost, forKey: costKey)
        userDefaults.set(requestCount, forKey: requestCountKey)

        print("🤖 AI Insights: Request cost $\(String(format: "%.4f", cost)) (Total: $\(String(format: "%.2f", totalCost)), \(requestCount) requests)")
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

enum AIInsightError: LocalizedError {
    case apiError(String)
    case invalidResponse
    case missingAPIKey
    case refused
    case truncated

    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "AI insight request failed: \(message)"
        case .invalidResponse:
            return "AI insight response could not be decoded"
        case .missingAPIKey:
            return "No Anthropic API key — add AnthropicConfig.plist with an AIKey entry"
        case .refused:
            return "The AI declined to generate this insight"
        case .truncated:
            return "AI insight response was cut off before it finished"
        }
    }
}

extension AIInsightsManager {
    
    /// Enhanced analysis that includes wellness metrics
    func analyzeWithWellness(
        summary: TrainingLoadSummary?,
        readiness: PhysiologicalReadiness?,
        recentLoads: [DailyTrainingLoad],
        wellnessMetrics: [DailyWellnessMetrics]
    ) async {
        guard Self.isEnabled else {
            print("🤖 AI Insights: Disabled")
            return
        }
        
        // Only analyze if there's something interesting OR we have wellness data
        guard shouldAnalyze(summary: summary, readiness: readiness) || !wellnessMetrics.isEmpty else {
            print("🤖 AI Insights: No analysis needed")
            return
        }
        
        // Rate limiting: Don't analyze more than once per 6 hours
        if let lastAnalysis = lastAnalysisDate,
           Date().timeIntervalSince(lastAnalysis) < 6 * 3600,
           !trainingChangedSinceLastInsight(recentLoads) {
            print("🤖 AI Insights: Too soon since last analysis")
            return
        }
 
        await generateWellnessEnhancedInsight(
            summary: summary,
            readiness: readiness,
            recentLoads: recentLoads,
            wellnessMetrics: wellnessMetrics
        )
    }
    
    private func generateWellnessEnhancedInsight(
        summary: TrainingLoadSummary?,
        readiness: PhysiologicalReadiness?,
        recentLoads: [DailyTrainingLoad],
        wellnessMetrics: [DailyWellnessMetrics]
    ) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let prompt = buildWellnessEnhancedPrompt(
                summary: summary,
                readiness: readiness,
                recentLoads: recentLoads,
                wellnessMetrics: wellnessMetrics
            )
            
            let insight = try await fetchInsight(prompt: prompt)
            currentInsight = insight
            lastAnalysisDate = Date()
            cacheInsight(insight)
            userDefaults.set(Self.trainingFingerprint(recentLoads), forKey: trainingFingerprintKey)
            print("🤖 AI Insights: Generated wellness-enhanced insight")

        } catch {
            print("🤖 AI Insights Error: \(error.localizedDescription)")
        }
        print("DEBUG: Current Insight is \(currentInsight == nil ? "NIL" : "SET")")
    }
    
    private func buildWellnessEnhancedPrompt(
        summary: TrainingLoadSummary?,
        readiness: PhysiologicalReadiness?,
        recentLoads: [DailyTrainingLoad],
        wellnessMetrics: [DailyWellnessMetrics]
    ) -> String {
        var prompt = """
        You are an expert cycling coach with expertise in sports science and recovery optimization.
        Analyze training data AND lifestyle/wellness data together for holistic insights.
        
        CRITICAL INSTRUCTIONS:
        1. Your response must be a single JSON object with this exact structure:
        {
          "priority": "critical" | "warning" | "info",
          "title": "Brief title (max 50 chars)",
          "insight": "Main insight (2-3 sentences, max 200 chars)",
          "explanation": "Why this matters (2-3 sentences, max 250 chars)",
          "recommendation": "Specific action to take (1-2 sentences, max 200 chars)",
          "confidence": "high" | "moderate" | "low"
        }
        
        2. PRIORITY HIERARCHY FOR ANALYSIS:
           - FIRST: Training load metrics (TSB, ATL, CTL, ramp rate)
           - SECOND: Physiological recovery (HRV, RHR, sleep quality)
           - THIRD: Sleep patterns and efficiency
           - LAST: Daily activity levels (steps are context only, not the focus)
        
        3. STEPS ARE CONTEXT ONLY:
           - Steps show general activity on non-training days
           - DO NOT recommend "increasing steps" as a primary action
           - DO NOT treat low steps as a problem if training volume is appropriate
           - On rest days, low steps may actually indicate good recovery
        
        4. FOCUS ON TRAINING-SPECIFIC INSIGHTS:
           - Training stress and recovery balance
           - Workout timing relative to recovery status
           - Sleep quality impact on training adaptation
           - When to push hard vs when to back off
        
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
            
            
            Physiological Readiness:
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
            }
        }
        
        // Add wellness metrics for last 7 days
        if !wellnessMetrics.isEmpty {
            prompt += """
            
            
            Recovery Context (Last 7 Days):
            """
            
            let avgSleepHours = wellnessMetrics.compactMap { $0.totalSleep }.reduce(0, +) / max(1, Double(wellnessMetrics.compactMap { $0.totalSleep }.count))
            prompt += "\n- Average sleep duration: \(String(format: "%.1f", avgSleepHours / 3600))h"
            
            let avgSleepEfficiency = wellnessMetrics.compactMap { $0.computedSleepEfficiency }.reduce(0, +) / max(1, Double(wellnessMetrics.compactMap { $0.computedSleepEfficiency }.count))
            prompt += "\n- Average sleep efficiency: \(String(format: "%.0f", avgSleepEfficiency))%"
            
            let avgActiveCalories = wellnessMetrics.compactMap { $0.activeEnergyBurned }.reduce(0, +) / max(1, Double(wellnessMetrics.compactMap { $0.activeEnergyBurned }.count))
            prompt += "\n- Average active calories: \(Int(avgActiveCalories)) kcal/day"
            
            // Include steps LAST and only as context
            let avgSteps = wellnessMetrics.compactMap { $0.steps }.reduce(0, +) / max(1, wellnessMetrics.compactMap { $0.steps }.count)
            prompt += "\n- Daily movement context: \(avgSteps) avg steps (context only)"
            
            // Add yesterday's specific data for context
            let calendar = Calendar.current
            let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
            let yesterdayData = wellnessMetrics
                .filter { calendar.isDate($0.date, inSameDayAs: yesterday) }
                .first
            
            if let yesterdayData = yesterdayData {
                prompt += "\n\nYesterday's Recovery:"
                if let sleep = yesterdayData.totalSleep {
                    prompt += "\n- Sleep: \(String(format: "%.1f", sleep / 3600))h"
                }
                // Only include sleep stages if available
                let hasStageData = yesterdayData.sleepDeep != nil || yesterdayData.sleepREM != nil || yesterdayData.sleepCore != nil
                if hasStageData {
                    var stages: [String] = []
                    if let deep = yesterdayData.sleepDeep {
                        stages.append("\(String(format: "%.1f", deep / 3600))h deep")
                    }
                    if let rem = yesterdayData.sleepREM {
                        stages.append("\(String(format: "%.1f", rem / 3600))h REM")
                    }
                    if let core = yesterdayData.sleepCore {
                        stages.append("\(String(format: "%.1f", core / 3600))h core")
                    }
                    if !stages.isEmpty {
                        prompt += "\n- Sleep stages: \(stages.joined(separator: ", "))"
                    }
                } else {
                    prompt += "\n- Sleep stages: Not available (device does not track sleep stages)"
                }
            }
        }
        
        prompt += Self.recentTrainingSection(from: recentLoads)
        
        prompt += """
        
        
        IMPORTANT: 
        - If sleep stages are marked "Not available", DO NOT mention deep sleep, REM, or sleep stages in your analysis.
        - Focus only on total sleep duration and sleep efficiency.
        - DO NOT recommend "increasing daily steps" as a primary action.
        - Steps are passive recovery context, not a training prescription.
        - Prioritize training load balance, sleep quality, and physiological readiness.
        
        Analyze ALL the data together - training load, physiological signals, AND lifestyle factors.
        Look for:
        1. Training stress vs recovery capacity (TSB vs sleep/HRV)
        2. Workout timing opportunities (good recovery = time to push)
        3. Overtraining warning signs (high fatigue + poor sleep/HRV)
        4. Recovery adequacy (is sleep supporting the training load?)
        
        Be specific and actionable. Connect training metrics to recovery status.
        Respond ONLY with the JSON object, no other text.
        """
        
        return prompt
    }
}

// MARK: - Wellness Summary Helper

extension WellnessManager {
    
    /// Get a quick text summary of wellness trends for AI context
    func getWeekSummaryText() -> String {
        guard let summary = currentSummary else {
            return "No wellness data available"
        }
        
        var text = ""
        
        if let avgSteps = summary.averageSteps {
            text += "Avg steps: \(Int(avgSteps))/day. "
        }
        
        if let avgSleep = summary.averageSleepHours {
            text += "Avg sleep: \(String(format: "%.1f", avgSleep))h/night. "
        }
        
        if let efficiency = summary.averageSleepEfficiency {
            text += "Sleep efficiency: \(Int(efficiency))%. "
        }
        
        if let debt = summary.sleepDebt, abs(debt) > 2 {
            text += "Sleep debt: \(abs(Int(debt)))h. "
        }
        
        if let trend = summary.activityTrend {
            if trend > 10 {
                text += "Activity trending up. "
            } else if trend < -10 {
                text += "Activity declining. "
            }
        }
        
        return text.isEmpty ? "No wellness trends detected" : text
    }
}

// MARK: - Recent training

extension AIInsightsManager {
    /// Actual (non-projected) loads for the last 7 calendar days ending today,
    /// oldest first. Callers pass the chart's `dailyLoads`, which is sorted
    /// oldest-first across the whole chart period and ends with projected
    /// days, so taking a prefix would send the *oldest* week and never today.
    static func lastSevenDays(of loads: [DailyTrainingLoad], now: Date = Date()) -> [DailyTrainingLoad] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return [] }
        return loads
            .filter { !$0.isProjected }
            .filter {
                let day = calendar.startOfDay(for: $0.date)
                return day >= start && day <= today
            }
            .sorted { $0.date < $1.date }
    }

    /// "Last 7 Days Training" prompt section, with today's entry labelled.
    static func recentTrainingSection(from loads: [DailyTrainingLoad], now: Date = Date()) -> String {
        let recent = lastSevenDays(of: loads, now: now)
        guard !recent.isEmpty else { return "" }
        let calendar = Calendar.current
        var section = "\n\nLast 7 Days Training (oldest first):"
        for load in recent {
            let dateStr = load.date.formatted(date: .abbreviated, time: .omitted)
            let label = calendar.isDate(load.date, inSameDayAs: now) ? " (TODAY)" : ""
            var line = "\n- \(dateStr)\(label): \(String(format: "%.0f", load.tss)) TSS"
            if load.rideCount > 0 {
                let minutes = Int((load.totalDuration / 60).rounded())
                line += ", \(load.rideCount) ride\(load.rideCount == 1 ? "" : "s"), \(minutes / 60)h \(minutes % 60)m"
            }
            section += line
        }
        if !recent.contains(where: { calendar.isDate($0.date, inSameDayAs: now) }) {
            section += "\n- Today: no training recorded yet"
        }
        return section
    }

    /// Changes whenever a ride is added or its TSS changes in the last week.
    static func trainingFingerprint(_ loads: [DailyTrainingLoad], now: Date = Date()) -> String {
        lastSevenDays(of: loads, now: now)
            .map { "\(Int($0.date.timeIntervalSince1970 / 86_400)):\($0.rideCount):\(Int($0.tss.rounded()))" }
            .joined(separator: ",")
    }

    /// True when the recent training differs from what the cached insight saw,
    /// so a just-finished workout isn't hidden behind the 6-hour rate limit.
    func trainingChangedSinceLastInsight(_ loads: [DailyTrainingLoad]) -> Bool {
        userDefaults.string(forKey: trainingFingerprintKey) != Self.trainingFingerprint(loads)
    }
}
