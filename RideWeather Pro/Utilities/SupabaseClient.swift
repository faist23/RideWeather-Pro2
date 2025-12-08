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
    
    // Fetch recent wellness data
    func fetchWellnessData(
        forUser userId: String,
        dataType: String? = nil,
        daysBack: Int = 7
    ) async throws -> [GarminWellnessRow] {
        var query = supabase
            .from("garmin_wellness")
            .select()
            .eq("user_id", value: userId)
        
        if let dataType = dataType {
            query = query.eq("data_type", value: dataType)
        }
        
        let response: [GarminWellnessRow] = try await query
            .order("calendar_date", ascending: false)
            .order("synced_at", ascending: false)
            .execute()
            .value
        
        return response
    }
    
    // Fetch dailies specifically
    func fetchDailySummaries(forUser userId: String, days: Int = 7) async throws -> [DailySummary] {
        let rows = try await fetchWellnessData(forUser: userId, dataType: "dailies", daysBack: days)
        
        return rows.compactMap { row -> DailySummary? in
            guard let dict = row.data.dictionary else { return nil }
            
            // Parse the Garmin daily summary format
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
    }
    
    // Fetch sleep data
    func fetchSleepData(forUser userId: String, days: Int = 7) async throws -> [SleepSummary] {
        let rows = try await fetchWellnessData(forUser: userId, dataType: "sleeps", daysBack: days)
        
        return rows.compactMap { row -> SleepSummary? in
            guard let dict = row.data.dictionary else { return nil }
            
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
    }
    
    // Fetch stress details
    func fetchStressData(forUser userId: String, days: Int = 7) async throws -> [StressSummary] {
        let rows = try await fetchWellnessData(forUser: userId, dataType: "stressDetails", daysBack: days)
        
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
        
        try await supabase
            .from("user_garmin_mapping")
            .upsert(mapping)
            .execute()
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
