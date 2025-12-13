//
//  SupabaseClient.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 12/6/25.
//


import Foundation
import Supabase

// MARK: - Supabase Configuration
class SupabaseManager {
    static let shared = SupabaseManager()
    
    let client: SupabaseClient
    
    private init() {

        let supabaseURL = URL(string: "https://ffndrszbbhngoiuezvyb.supabase.co")!
        let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZmbmRyc3piYmhuZ29pdWV6dnliIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ5ODc1OTAsImV4cCI6MjA4MDU2MzU5MH0.IGp-nG1vaHo_qTVNJwvkow9jsyQBpAOXuSfBwbQrcW0"
        
        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    // Fix the warning by opting into the new behavior
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
}

// MARK: - Data Models
struct GarminWellnessRow: Codable {
    let id: UUID
    let userId: String
    let garminUserId: String
    let dataType: String
    let data: JSONValue // Changed from AnyCodable
    let calendarDate: String?
    let syncedAt: Date
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, data
        case userId = "user_id"
        case garminUserId = "garmin_user_id"
        case dataType = "data_type"
        case calendarDate = "calendar_date"
        case syncedAt = "synced_at"
        case createdAt = "created_at"
    }
}

// Helper for flexible JSON
enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid JSON value")
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
    
    // Helper to extract dictionary
    var dictionary: [String: Any]? {
        guard case .object(let dict) = self else { return nil }
        return dict.mapValues { $0.anyValue }
    }
    
    var anyValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        case .object(let value): return value.mapValues { $0.anyValue }
        case .array(let value): return value.map { $0.anyValue }
        case .null: return NSNull()
        }
    }
}

// MARK: - Wellness Data Service
class WellnessDataService {
    private let supabase = SupabaseManager.shared.client
    
    // Get Garmin User ID from app user ID
    func getGarminUserId(forAppUser appUserId: String) async throws -> String? {
        print("   📡 Querying user_garmin_mapping table...")
        print("   Looking for user_id: \(appUserId)")
        
        struct UserMapping: Codable {
            let user_id: String
            let garmin_user_id: String
            let connected_at: String?
            
            enum CodingKeys: String, CodingKey {
                case user_id
                case garmin_user_id
                case connected_at
            }
        }
        
        do {
            let response: [UserMapping] = try await supabase
                .from("user_garmin_mapping")
                .select()
                .eq("user_id", value: appUserId)
                .limit(1)
                .execute()
                .value
            
            if let mapping = response.first {
                print("   ✅ Found mapping:")
                print("      app_user_id: \(mapping.user_id)")
                print("      garmin_user_id: \(mapping.garmin_user_id)")
                if let connected = mapping.connected_at {
                    print("      connected_at: \(connected)")
                }
                return mapping.garmin_user_id
            } else {
                print("   ❌ No mapping found in user_garmin_mapping table")
                print("   This means linkToSupabase() was never called or failed")
                return nil
            }
            
        } catch {
            print("   ❌ Database query error: \(error)")
            throw error
        }
    }
    
    // ============================================================================
    // REPLACE YOUR fetchWellnessData METHOD WITH THIS VERSION
    // This queries using garmin_user_id instead of user_id
    // ============================================================================

    func fetchWellnessData(
        forUser userId: String,
        garminUserId: String? = nil,
        dataType: String? = nil,
        daysBack: Int = 7
    ) async throws -> [GarminWellnessRow] {
        print("   📡 Fetching from garmin_wellness table...")
        print("      app_user_id: \(userId)")
        if let garminId = garminUserId {
            print("      garmin_user_id: \(garminId)")
        }
        if let type = dataType {
            print("      data_type: \(type)")
        }
        
        // Build query step by step for debugging
        var query = supabase
            .from("garmin_wellness")
            .select()
        
        // Add filters
        if let garminId = garminUserId {
            print("   🔍 Adding filter: garmin_user_id = '\(garminId)'")
            query = query.eq("garmin_user_id", value: garminId)
        } else {
            print("   🔍 Adding filter: user_id = '\(userId)'")
            query = query.eq("user_id", value: userId)
        }
        
        if let dataType = dataType {
            print("   🔍 Adding filter: data_type = '\(dataType)'")
            query = query.eq("data_type", value: dataType)
        }
        
        print("   📤 Executing query...")
        
        do {
            let response: [GarminWellnessRow] = try await query
                .order("calendar_date", ascending: false)
                .order("synced_at", ascending: false)
                .execute()
                .value
            
            print("   ✅ Retrieved \(response.count) rows")
            
            if response.isEmpty {
                print("   ⚠️ Query returned empty. Trying raw query to test...")
                
                // Try a completely raw query without filters
                let testQuery = supabase
                    .from("garmin_wellness")
                    .select()
                    .limit(5)
                
                let testResponse: [GarminWellnessRow] = try await testQuery
                    .execute()
                    .value
                
                print("   🧪 Test query (no filters, limit 5): \(testResponse.count) rows")
                if !testResponse.isEmpty {
                    print("   📋 Sample row from test:")
                    if let first = testResponse.first {
                        print("      user_id: \(first.userId)")
                        print("      garmin_user_id: \(first.garminUserId)")
                        print("      data_type: \(first.dataType)")
                    }
                }
            } else {
                print("   📋 Sample data:")
                if let first = response.first {
                    print("      user_id: \(first.userId)")
                    print("      garmin_user_id: \(first.garminUserId)")
                    print("      data_type: \(first.dataType)")
                    print("      calendar_date: \(first.calendarDate ?? "null")")
                }
            }
            
            return response
            
        } catch {
            print("   ❌ Query error: \(error)")
            print("   Error type: \(type(of: error))")
            throw error
        }
    }

    // ============================================================================
    // UPDATE fetchDailySummaries to pass garminUserId
    // ============================================================================

    func fetchDailySummaries(forUser userId: String, garminUserId: String? = nil, days: Int = 7) async throws -> [DailySummary] {
        print("\n📊 Fetching daily summaries...")
        let rows = try await fetchWellnessData(forUser: userId, garminUserId: garminUserId, dataType: "dailies", daysBack: days)
        
        print("   Processing \(rows.count) daily summary rows...")
        
        let summaries = rows.compactMap { row -> DailySummary? in
            guard let dict = row.data.dictionary else {
                print("   ⚠️ Row \(row.id): Failed to parse data dictionary")
                return nil
            }
            
            // Log what we found
            if let date = row.calendarDate {
                print("   ✅ \(date): steps=\(dict["steps"] as? Int ?? 0), calories=\(dict["activeKilocalories"] as? Int ?? 0)")
            }
            
            return DailySummary(
                id: row.id,
                calendarDate: row.calendarDate ?? "",
                steps: dict["steps"] as? Int,
                activeKilocalories: dict["activeKilocalories"] as? Int,
                distanceInMeters: dict["distanceInMeters"] as? Double,
                durationInSeconds: dict["durationInSeconds"] as? Int,
                averageHeartRate: dict["averageHeartRateInBeatsPerMinute"] as? Int,
                restingHeartRate: dict["restingHeartRateInBeatsPerMinute"] as? Int,
                syncedAt: row.syncedAt
            )
        }
        
        print("   Parsed \(summaries.count) valid summaries")
        return summaries
    }

    // ============================================================================
    // UPDATE fetchSleepData to pass garminUserId
    // ============================================================================

    func fetchSleepData(forUser userId: String, garminUserId: String? = nil, days: Int = 7) async throws -> [SleepSummary] {
        print("\n😴 Fetching sleep data...")
        let rows = try await fetchWellnessData(forUser: userId, garminUserId: garminUserId, dataType: "sleeps", daysBack: days)
        
        print("   Processing \(rows.count) sleep rows...")
        
        let summaries = rows.compactMap { row -> SleepSummary? in
            guard let dict = row.data.dictionary else {
                print("   ⚠️ Row \(row.id): Failed to parse data dictionary")
                return nil
            }
            
            // Log what we found
            if let date = row.calendarDate {
                let totalSleep = (dict["deepSleepDurationInSeconds"] as? Int ?? 0) +
                                (dict["lightSleepDurationInSeconds"] as? Int ?? 0) +
                                (dict["remSleepInSeconds"] as? Int ?? 0)
                print("   ✅ \(date): total_sleep=\(String(format: "%.1f", Double(totalSleep) / 3600))h")
            }
            
            return SleepSummary(
                id: row.id,
                calendarDate: row.calendarDate ?? "",
                durationInSeconds: dict["durationInSeconds"] as? Int,
                deepSleepDurationInSeconds: dict["deepSleepDurationInSeconds"] as? Int,
                lightSleepDurationInSeconds: dict["lightSleepDurationInSeconds"] as? Int,
                remSleepInSeconds: dict["remSleepInSeconds"] as? Int,
                awakeDurationInSeconds: dict["awakeDurationInSeconds"] as? Int,
                validation: dict["validation"] as? String,
                syncedAt: row.syncedAt
            )
        }
        
        print("   Parsed \(summaries.count) valid sleep records")
        return summaries
    }
    // Fetch stress details
    func fetchStressData(forUser userId: String, garminUserId: String? = nil, days: Int = 7) async throws -> [StressSummary] {
        let rows = try await fetchWellnessData(forUser: userId, garminUserId: garminUserId, dataType: "stressDetails", daysBack: days)
        
        return rows.compactMap { row -> StressSummary? in
            guard let dict = row.data.dictionary else { return nil }
            
            return StressSummary(
                id: row.id,
                calendarDate: row.calendarDate ?? "",
                averageStressLevel: dict["averageStressLevel"] as? Int,
                maxStressLevel: dict["maxStressLevel"] as? Int,
                restStressDuration: dict["restStressDurationInSeconds"] as? Int,
                lowStressDuration: dict["lowStressDurationInSeconds"] as? Int,
                mediumStressDuration: dict["mediumStressDurationInSeconds"] as? Int,
                highStressDuration: dict["highStressDurationInSeconds"] as? Int,
                syncedAt: row.syncedAt
            )
        }
    }
    
    // Map Garmin user to app user
    func linkGarminUser(appUserId: String, garminUserId: String) async throws {
        print("\n🔗 Linking Garmin user to app user...")
        print("   app_user_id: \(appUserId)")
        print("   garmin_user_id: \(garminUserId)")
        
        struct UserMapping: Encodable {
            let user_id: String
            let garmin_user_id: String
            let connected_at: String
        }
        
        let mapping = UserMapping(
            user_id: appUserId,
            garmin_user_id: garminUserId,
            connected_at: Date().ISO8601Format()
        )
        
        do {
            try await supabase
                .from("user_garmin_mapping")
                .upsert(mapping, onConflict: "user_id")
                .execute()
            
            print("   ✅ Mapping saved successfully")
        } catch {
            print("   ❌ Failed to save mapping: \(error)")
            throw error
        }
    }
}

// MARK: - Domain Models
struct DailySummary: Identifiable {
    let id: UUID
    let calendarDate: String
    let steps: Int?
    let activeKilocalories: Int?
    let distanceInMeters: Double?
    let durationInSeconds: Int?
    let averageHeartRate: Int?
    let restingHeartRate: Int?
    let syncedAt: Date
}

struct SleepSummary: Identifiable {
    let id: UUID
    let calendarDate: String
    let durationInSeconds: Int?
    let deepSleepDurationInSeconds: Int?
    let lightSleepDurationInSeconds: Int?
    let remSleepInSeconds: Int?
    let awakeDurationInSeconds: Int?
    let validation: String?
    let syncedAt: Date
}

struct StressSummary: Identifiable {
    let id: UUID
    let calendarDate: String
    let averageStressLevel: Int?
    let maxStressLevel: Int?
    let restStressDuration: Int?
    let lowStressDuration: Int?
    let mediumStressDuration: Int?
    let highStressDuration: Int?
    let syncedAt: Date
}

extension WellnessDataService {
    
    /// Save a daily summary to Supabase
    func saveDailySummary(appUserId: String, garminUserId: String, summary: GarminDailySummary) async throws {
        
        struct WellnessRow: Encodable {
            let user_id: String
            let garmin_user_id: String
            let data_type: String
            let calendar_date: String
            let data: [String: Any]
            let synced_at: String
            
            enum CodingKeys: String, CodingKey {
                case user_id, garmin_user_id, data_type, calendar_date, data, synced_at
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(user_id, forKey: .user_id)
                try container.encode(garmin_user_id, forKey: .garmin_user_id)
                try container.encode(data_type, forKey: .data_type)
                try container.encode(calendar_date, forKey: .calendar_date)
                try container.encode(synced_at, forKey: .synced_at)
                
                // Encode data as JSON
                let jsonData = try JSONSerialization.data(withJSONObject: data)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                try container.encode(jsonString, forKey: .data)
            }
        }
        
        // Convert summary to dictionary
        var dataDict: [String: Any] = [:]
        if let steps = summary.steps { dataDict["steps"] = steps }
        if let distance = summary.distanceInMeters { dataDict["distanceInMeters"] = distance }
        if let active = summary.activeTimeInSeconds { dataDict["activeTimeInSeconds"] = active }
        if let calories = summary.activeKilocalories { dataDict["activeKilocalories"] = calories }
        if let bmr = summary.bmrKilocalories { dataDict["bmrKilocalories"] = bmr }
        if let rhr = summary.restingHeartRate { dataDict["restingHeartRateInBeatsPerMinute"] = rhr }
        
        let row = WellnessRow(
            user_id: appUserId,
            garmin_user_id: garminUserId,
            data_type: "dailies",
            calendar_date: summary.calendarDate,
            data: dataDict,
            synced_at: Date().ISO8601Format()
        )
        
        try await supabase
            .from("garmin_wellness")
            .upsert(row)
            .execute()
    }
    
    /// Save sleep data to Supabase
    func saveSleepData(appUserId: String, garminUserId: String, sleep: GarminSleepData) async throws {
        
        struct WellnessRow: Encodable {
            let user_id: String
            let garmin_user_id: String
            let data_type: String
            let calendar_date: String
            let data: [String: Any]
            let synced_at: String
            
            enum CodingKeys: String, CodingKey {
                case user_id, garmin_user_id, data_type, calendar_date, data, synced_at
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(user_id, forKey: .user_id)
                try container.encode(garmin_user_id, forKey: .garmin_user_id)
                try container.encode(data_type, forKey: .data_type)
                try container.encode(calendar_date, forKey: .calendar_date)
                try container.encode(synced_at, forKey: .synced_at)
                
                // Encode data as JSON
                let jsonData = try JSONSerialization.data(withJSONObject: data)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                try container.encode(jsonString, forKey: .data)
            }
        }
        
        // Convert sleep to dictionary
        var dataDict: [String: Any] = [:]
        if let total = sleep.sleepTimeSeconds { dataDict["durationInSeconds"] = total }
        if let deep = sleep.deepSleepSeconds { dataDict["deepSleepDurationInSeconds"] = deep }
        if let light = sleep.lightSleepSeconds { dataDict["lightSleepDurationInSeconds"] = light }
        if let rem = sleep.remSleepSeconds { dataDict["remSleepInSeconds"] = rem }
        if let awake = sleep.awakeSleepSeconds { dataDict["awakeDurationInSeconds"] = awake }
        
        let row = WellnessRow(
            user_id: appUserId,
            garmin_user_id: garminUserId,
            data_type: "sleeps",
            calendar_date: sleep.calendarDate,
            data: dataDict,
            synced_at: Date().ISO8601Format()
        )
        
        try await supabase
            .from("garmin_wellness")
            .upsert(row)
            .execute()
    }
}

