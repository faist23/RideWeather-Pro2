//
//  WahooService.swift
//  RideWeather Pro
//

import Foundation
import AuthenticationServices
import Combine
import UIKit
import CoreLocation
import CryptoKit
import FitFileParser

// MARK: - API Data Models

// MARK: - Workout List/API Wrapper
struct WahooWorkoutsResponse: Codable {
    let workouts: [WahooWorkoutSummary]
    let total: Int?
    let page: Int?
    let perPage: Int?
    let order: String?
    let sort: String?
}

struct WahooTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval
}

struct WahooTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
}

struct WahooUser: Decodable {
    let id: Int?
    let firstName: String?  // Maps from "first"
    let lastName: String?   // Maps from "last"
    let email: String?
    let height: String?     // API returns string like "1.7526"
    let weight: String?     // API returns string like "69.3"
    let birth: String?
    let gender: Int?        // API returns 0 or 1
    let createdAt: String?
    let updatedAt: String?
    
    // CodingKeys to map API field names to Swift property names
    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first"      // "first" → firstName
        case lastName = "last"        // "last" → lastName
        case email
        case height
        case weight
        case birth
        case gender
        case createdAt = "created_at" // snake_case → camelCase
        case updatedAt = "updated_at" // snake_case → camelCase
    }
    
    // Computed property for full name
    var fullName: String {
        let first = firstName ?? ""
        let last = lastName ?? ""
        let combined = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return combined.isEmpty ? "Wahoo User" : combined
    }
    
    // Computed property for first name only
    var displayFirstName: String {
        return firstName ?? "Wahoo User"
    }
    
    // Helper to get weight as Double if needed
    var weightKg: Double? {
        guard let weight = weight else { return nil }
        return Double(weight)
    }
    
    // Helper to get height as Double if needed
    var heightMeters: Double? {
        guard let height = height else { return nil }
        return Double(height)
    }
}

// MARK: - Workout File struct (inside workout_summary)
struct WahooWorkoutFile: Codable {
    let url: String?
    let fitnessAppId: Int?
}

// MARK: - Workout Summary Detail struct (workout_summary)
struct WahooWorkoutSummaryDetail: Codable {
    let id: Int?
    let name: String?
    let ascentAccum: String?
    let cadenceAvg: String?
    let caloriesAccum: String?
    let distanceAccum: String?
    let durationActiveAccum: String?
    let durationPausedAccum: String?
    let durationTotalAccum: String?
    let heartRateAvg: String?
    let powerBikeNpLast: String?
    let powerBikeTssLast: String?
    let powerAvg: String?
    let speedAvg: String?
    let workAccum: String?
    let timeZone: String?
    let manual: Bool?
    let edited: Bool?
    let file: WahooWorkoutFile?
    let files: [WahooWorkoutFile]?
    let fitnessAppId: Int?
    let createdAt: String?
    let updatedAt: String?
}

// MARK: - Workout Summary struct (for both list & detail)
struct WahooWorkoutSummary: Codable, Identifiable {
    let id: Int
    let starts: String?
    let minutes: Int?
    let name: String?
    let planId: Int?
    let planIds: [Int]?
    let routeId: Int?
    let workoutToken: String?
    let workoutTypeId: Int?
    let dayCode: String?
    let workoutSummary: WahooWorkoutSummaryDetail?
    let fitnessAppId: Int?
    let createdAt: String?
    let updatedAt: String?
    
    var rideDate: Date? {
        guard let starts else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: starts)
    }
    var displayName: String {
        workoutSummary?.name ?? name ?? "Cycling"
    }
}

extension WahooWorkoutSummary {
    var movingTimeSeconds: Int {
        Int(Double(workoutSummary?.durationActiveAccum ?? "0") ?? 0)
    }
    var elapsedTimeSeconds: Int {
        Int(Double(workoutSummary?.durationTotalAccum ?? "0") ?? 0)
    }
    var movingTimeFormatted: String {
        formatDuration(seconds: movingTimeSeconds)
    }
    var elapsedTimeFormatted: String {
        formatDuration(seconds: elapsedTimeSeconds)
    }
    private func formatDuration(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%dh %dm", h, m)
        } else if m > 0 {
            return String(format: "%dm %ds", m, s)
        } else {
            return String(format: "%ds", s)
        }
    }
    var distanceMiles: Double {
        (Double(workoutSummary?.distanceAccum ?? "0") ?? 0) / 1609.34
    }
    var distanceKm: Double {
        (Double(workoutSummary?.distanceAccum ?? "0") ?? 0) / 1000.0
    }
}

extension WahooWorkoutSummary {
    // Get duration in seconds from nested summary (which is a string)
    var durationTotal: Int {
        Int(workoutSummary?.durationTotalAccum ?? "0") ?? 0
    }
    var durationFormatted: String {
        let seconds = durationTotal
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%dh %dm", h, m)
        } else if m > 0 {
            return String(format: "%dm %ds", m, s)
        } else {
            return String(format: "%ds", s)
        }
    }
}
extension WahooWorkoutSummary {
    var work: Double {
        Double(workoutSummary?.workAccum ?? "0") ?? 0
    }
}
extension WahooWorkoutSummary {
    var durationActive: Double {
        Double(workoutSummary?.durationActiveAccum ?? "0") ?? 0
    }
}


// 3. The "streams" struct
struct WahooWorkoutData: Decodable {
    let time: [Double]?
    let power: [Int]?
    let heartrate: [Int]?
    let cadence: [Int]?
    let speed: [Double]?
    let distance: [Double]?
    let altitude: [Double]?
    let positionLat: [Double]?
    let positionLong: [Double]?
}

// MARK: - Main Service
@MainActor
class WahooService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    
    // (All configuration, published, and internal state properties are correct)
    private var wahooConfig: [String: String]?
    private var clientId: String { configValue(forKey: "WahooClientID") ?? "INVALID_CLIENT_ID" }
    private var clientSecret: String { configValue(forKey: "WahooClientSecret") ?? "INVALID_CLIENT_SECRET" }
    private let apiBaseUrl = "https://api.wahooligan.com"
    private let redirectUri = "https://faist23.github.io/rideweatherpro-redirect/wahoo-redirect.html"
    private let scope = "user_write power_zones_read workouts_read plans_read plans_write routes_read routes_write offline_data user_read"
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String? = nil
    @Published var athleteName: String? = nil
    private var webAuthSession: ASWebAuthenticationSession?
    private var currentPkceVerifier: String?
    private var currentTokens: WahooTokens? {
        didSet {
            isAuthenticated = currentTokens != nil
            saveTokensToKeychain()
        }
    }
    private let athleteNameKey = "wahoo_athlete_name"
    
    // (init is correct)
    override init() {
        super.init()
        loadConfig()
        loadTokensFromKeychain()
        loadAthleteNameFromKeychain()
    }
    
    // (loadConfig and configValue are correct)
    private func loadConfig() {
        guard let path = Bundle.main.path(forResource: "WahooConfig", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            print("🚨 WahooService FATAL ERROR: WahooConfig.plist missing or malformed.")
            errorMessage = "Critical configuration error. Wahoo disabled."
            wahooConfig = nil
            return
        }
        wahooConfig = dict
        print("WahooService: Configuration loaded.")
    }
    private func configValue(forKey key: String) -> String? {
        return wahooConfig?[key]
    }
    
    // (authenticate and handleRedirect are correct)
    func authenticate() {
        guard wahooConfig != nil,
              clientId != "INVALID_CLIENT_ID" else {
            errorMessage = "Invalid Wahoo configuration."
            return
        }
        
        let pkce = generatePKCE()
        self.currentPkceVerifier = pkce.verifier
        
        var components = URLComponents(string: "\(apiBaseUrl)/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authURL = components.url else { return }
        
        webAuthSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "rideweatherpro"
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            if let error = error {
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    print("WahooService: Login canceled.")
                } else {
                    self.errorMessage = error.localizedDescription
                }
                return
            }
            guard let url = callbackURL else { return }
            self.handleRedirect(url: url)
        }
        webAuthSession?.presentationContextProvider = self
        webAuthSession?.prefersEphemeralWebBrowserSession = true
        _ = webAuthSession?.start()
    }
    func handleRedirect(url: URL) {
        guard url.scheme == "rideweatherpro",
              url.host == "wahoo-auth",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return
        }
        guard let pkceVerifier = self.currentPkceVerifier else {
            errorMessage = "Authentication failed: PKCE verifier was lost."
            return
        }
        exchangeToken(code: code, pkceVerifier: pkceVerifier)
    }
    
    private func exchangeToken(code: String, pkceVerifier: String) {
        guard let tokenURL = URL(string: "\(apiBaseUrl)/oauth/token") else { return }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "code_verifier", value: pkceVerifier)
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            Task { @MainActor in
                if let error = error {
                    self.errorMessage = error.localizedDescription; return
                }
                guard let data = data else { return }
                
                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase // <-- FIX
                    let tokenResponse = try decoder.decode(WahooTokenResponse.self, from: data)
                    
                    self.currentTokens = WahooTokens(
                        accessToken: tokenResponse.accessToken,
                        refreshToken: tokenResponse.refreshToken,
                        expiresAt: Date().timeIntervalSince1970 + tokenResponse.expiresIn
                    )
                    self.errorMessage = nil
                    await self.fetchUserName()
                } catch {
                    print("WahooService: Token decoding error: \(error)")
                    if let errorBody = String(data: data, encoding: .utf8) {
                        print("WahooService: Error body: \(errorBody)")
                    }
                    self.errorMessage = "Token decoding failed."
                }
            }
        }.resume()
    }
    
    func refreshTokenIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tokens = currentTokens else {
            completion(.failure(WahooError.notAuthenticated)); return
        }
        if Date().timeIntervalSince1970 < tokens.expiresAt - 3600 {
            completion(.success(())); return
        }
        
        print("WahooService: Refreshing token...")
        guard let tokenURL = URL(string: "\(apiBaseUrl)/oauth/token") else {
            completion(.failure(WahooError.invalidURL)); return
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "refresh_token", value: tokens.refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            Task { @MainActor in
                if let error = error {
                    self.disconnect(); completion(.failure(error)); return
                }
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                    self.disconnect(); completion(.failure(WahooError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1))); return
                }
                
                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase // <-- FIX
                    let tokenResponse = try decoder.decode(WahooTokenResponse.self, from: data)
                    
                    self.currentTokens = WahooTokens(
                        accessToken: tokenResponse.accessToken,
                        refreshToken: tokenResponse.refreshToken,
                        expiresAt: Date().timeIntervalSince1970 + tokenResponse.expiresIn
                    )
                    self.errorMessage = nil
                    completion(.success(()))
                } catch {
                    self.disconnect(); completion(.failure(error))
                }
            }
        }.resume()
    }
    
    func disconnect() {
        currentTokens = nil
        athleteName = nil
        deleteAthleteNameFromKeychain()
        isAuthenticated = false
    }
    
    // Keychain functions must use a *default* decoder/encoder ---
    // We are encoding our *own* Swift struct (WahooTokens), which is already camelCase.
    private let keychainService = Bundle.main.bundleIdentifier ?? "com.rideweatherpro.wahoo"
    private let keychainAccount = "wahooUserTokensV1"
    
    private func saveTokensToKeychain() {
        guard let tokens = currentTokens else {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainAccount]
            SecItemDelete(query as CFDictionary)
            return
        }
        do {
            let encoder = JSONEncoder() // <-- Default encoder (no strategy)
            let data = try encoder.encode(tokens)
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainAccount, kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            SecItemDelete(query as CFDictionary)
            SecItemAdd(query as CFDictionary, nil)
        } catch {
            print("WahooService: Failed to save tokens: \(error)")
        }
    }
    private func loadTokensFromKeychain() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainAccount, kSecReturnData as String: kCFBooleanTrue!, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            do {
                let decoder = JSONDecoder() // <-- Default decoder (no strategy)
                self.currentTokens = try decoder.decode(WahooTokens.self, from: data)
                if Date().timeIntervalSince1970 >= (currentTokens?.expiresAt ?? 0) - 3600 {
                    refreshTokenIfNeeded { _ in }
                }
            } catch {
                self.currentTokens = nil; saveTokensToKeychain()
            }
        }
    }
    // (Keychain name methods are correct)
    private func saveAthleteNameToKeychain(_ name: String) {
        let data = Data(name.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: athleteNameKey, kSecValueData as String: data]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    private func loadAthleteNameFromKeychain() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: athleteNameKey, kSecReturnData as String: kCFBooleanTrue!, kSecMatchLimit as String: kSecMatchLimitOne]
        var ref: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess, let data = ref as? Data, let name = String(data: data, encoding: .utf8) {
            athleteName = name
        }
    }
    private func deleteAthleteNameFromKeychain() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: athleteNameKey]
        SecItemDelete(query as CFDictionary)
    }
    
    // (Presentation Anchor, PKCE, API Helper are correct)
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Get the key window scene (modern way)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            // Return the scene's key window, or create a UIWindow for that scene (never global UIWindow())
            return UIWindow(windowScene: windowScene)
        }
        // Fallback if nothing found
        fatalError("No valid UIWindowScene found for authentication presentation")
    }
    
    private func generatePKCE() -> (verifier: String, challenge: String) {
        let verifier = Data.random(length: 32).base64URLEncodedString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        return (verifier, challenge)
    }
    
    private func refreshTokenIfNeededAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            refreshTokenIfNeeded { result in
                continuation.resume(with: result)
            }
        }
    }
    
    // MARK: - API Methods
        
    func fetchUserName() async {
        try? await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { return }
        
        guard let url = URL(string: "\(apiBaseUrl)/v1/user") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Debug logging
            if let responseString = String(data: data, encoding: .utf8) {
                print("WahooService: User API response: \(responseString)")
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("WahooService: Invalid response type")
                self.athleteName = "Wahoo User"
                saveAthleteNameToKeychain("Wahoo User")
                return
            }
            
            print("WahooService: User API status code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                print("WahooService: Could not fetch user name (status: \(httpResponse.statusCode))")
                self.athleteName = "Wahoo User"
                saveAthleteNameToKeychain("Wahoo User")
                return
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            do {
                let user = try decoder.decode(WahooUser.self, from: data)
                
                let firstName = user.firstName ?? "Wahoo User"
                let lastName = user.lastName ?? ""
                let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                let finalName = fullName.isEmpty ? "Wahoo User" : fullName
                
                self.athleteName = firstName
                saveAthleteNameToKeychain(firstName)
                
                print("WahooService: User authenticated as \(finalName)")
                
            } catch {
                print("WahooService: Could not decode user data: \(error)")
                print("WahooService: Decoding error details: \(error.localizedDescription)")
                
                // Fallback to generic name
                self.athleteName = "Wahoo User"
                saveAthleteNameToKeychain("Wahoo User")
            }
            
        } catch {
            print("WahooService: Network error fetching user name: \(error.localizedDescription)")
            self.athleteName = "Wahoo User"
            saveAthleteNameToKeychain("Wahoo User")
        }
    }
    
    // Fetch workouts list
    func fetchRecentWorkouts(page: Int, perPage: Int = 50) async throws -> WahooWorkoutsResponse {
        try await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { throw WahooError.notAuthenticated }
        var components = URLComponents(string: "\(apiBaseUrl)/v1/workouts")!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "sort", value: "-starts"),
            URLQueryItem(name: "workout_type_id", value: "0")
        ]
        guard let url = components.url else { throw WahooError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                print("WahooService: Error fetching workouts: \(errorBody)")
            }
            throw WahooError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        
        // Print HTTP status code
        if let httpResponse = response as? HTTPURLResponse {
            print("WahooService: HTTP status code:", httpResponse.statusCode)
        }
        
        // Print raw JSON or data string
        if let jsonString = String(data: data, encoding: .utf8) {
            print("WahooService Raw Workouts JSON:", jsonString)
        } else {
            print("WahooService: No JSON could be decoded")
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(WahooWorkoutsResponse.self, from: data)
            return response
        } catch {
            print("🚨 WahooService: Decoding error:", error)
            print("WahooService: Raw data as string:", String(data: data, encoding: .utf8) ?? "nil")
            throw error
        }
    }
    
    
    // Fetch workout detail by ID
    func fetchWorkoutDetail(id: Int) async throws -> WahooWorkoutSummary {
        // Ensure your token logic matches your app's auth flow:
        try await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { throw WahooError.notAuthenticated }
        let url = URL(string: "\(apiBaseUrl)/v1/workouts/\(id)")!
        var request = URLRequest(url: url)
        
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8)
            print("Error loading detail for id \(id):", errorBody ?? "nil")
            throw WahooError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        print("Workout detail raw JSON:", String(data: data, encoding: .utf8) ?? "nil")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(WahooWorkoutSummary.self, from: data)
    }
    
    // (fetchWorkoutData) - Now uses .convertFromSnakeCase
    func fetchWorkoutData(id: Int) async throws -> WahooWorkoutData {
        try await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { throw WahooError.notAuthenticated }
        
        guard let url = URL(string: "\(apiBaseUrl)/v1/workouts/\(id)/data") else {
            throw WahooError.invalidURL
        }
        print("url: ", url)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let jsonString = String(data: data, encoding: .utf8) {
            print("WahooService Raw Workouts JSON:", jsonString)
        }
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WahooError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase // <-- FIX
        return try decoder.decode(WahooWorkoutData.self, from: data)
    }
    
    /// Extracts GPS route from a Wahoo Activity
    func extractRouteFromActivity(activityId: Int) async throws -> (coordinates: [CLLocationCoordinate2D], elevationAnalysis: ElevationAnalysis?) {
        try await refreshTokenIfNeededAsync()
        
        // 1. Fetch the workout summary which contains the .fit file URL
        print("WahooService: Fetching workout detail for \(activityId)...")
        let workoutDetail = try await fetchWorkoutDetail(id: activityId)
        
        // 2. Get the .fit file URL from the response
        guard let fitFileUrlString = workoutDetail.workoutSummary?.file?.url,
              let fitFileUrl = URL(string: fitFileUrlString) else {
            print("WahooService: No .fit file URL found in workout summary.")
            throw WahooError.noRouteData
        }
        
        print("WahooService: Downloading .fit file from \(fitFileUrl)...")
        
        // 3. Download the .fit file data
        let (fileData, response) = try await URLSession.shared.data(from: fitFileUrl)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("WahooService: Failed to download .fit file. Status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            throw WahooError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        print("WahooService: Downloaded \(fileData.count) bytes. Parsing file...")
        
        // 4. Parse the .fit file data
        let parser = RouteParser()
        // Use the parser that correctly generates ElevationAnalysis
        let parseResult = try parser.parseWithElevation(fitData: fileData)
        
        guard !parseResult.coordinates.isEmpty else {
            print("WahooService: Parser found no coordinates in the .fit file.")
            throw WahooError.noRouteData
        }
        
        print("WahooService: Extracted \(parseResult.coordinates.count) GPS points and elevation data from activity \(activityId)")
        
        // Return BOTH coordinates and the already-calculated elevation analysis
        return (coordinates: parseResult.coordinates, elevationAnalysis: parseResult.elevationAnalysis)
    }
    
    func uploadRouteToWahoo(fitData: Data, routeName: String) async throws {
        try await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { throw WahooError.notAuthenticated }
        
        guard let url = URL(string: "\(apiBaseUrl)/v1/routes") else {
            throw WahooError.invalidURL
        }
        
        // 1. Create a unique boundary for the multipart request
        let boundary = "Boundary-\(UUID().uuidString)"
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // 2. Set the Content-Type to multipart/form-data
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // 3. Manually build the multipart body
        var body = Data()
        
        // Helper to append form data fields
        let boundaryPrefix = "--\(boundary)\r\n"
        
        func appendFormField(named name: String, value: String) {
            body.append(boundaryPrefix.data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
                
        // Sanitize the route name (same as before)
        let allowedChars = CharacterSet.alphanumerics.union(.whitespaces).union(.init(charactersIn: "-_"))
        let sanitizedName = String(routeName.unicodeScalars.filter(allowedChars.contains))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "-.", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-._ "))
            .prefix(50)
        
        // Extract route metadata from FIT file (same as before)
        let parser = RouteParser()
        let startCoordinate: CLLocationCoordinate2D
        var routeDistanceMeters: Double = 0  // <-- Keep in METERS
        var routeAscent: Double = 0
        
        if let result = try? parser.parseWithElevation(fitData: fitData) {
            startCoordinate = result.coordinates.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            routeDistanceMeters = result.elevationAnalysis?.elevationProfile.last?.distance ?? 0 // Keep in meters!
            routeAscent = result.elevationAnalysis?.totalGain ?? 0 // meters
        } else {
            startCoordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        
        let externalId = "rideweatherpro-\(UUID().uuidString)"
        let filename = "\(sanitizedName.replacingOccurrences(of: " ", with: "_")).fit"
        
        // 4. Append all the text parameters using the helper
        appendFormField(named: "route[name]", value: String(sanitizedName))
        appendFormField(named: "route[external_id]", value: externalId)
        appendFormField(named: "route[workout_type_family_id]", value: "0") // 0 = cycling
        appendFormField(named: "route[start_lat]", value: String(startCoordinate.latitude))
        appendFormField(named: "route[start_lng]", value: String(startCoordinate.longitude))
        appendFormField(named: "route[distance]", value: String(format: "%.2f", routeDistanceMeters)) // <-- Send METERS, not km
        appendFormField(named: "route[ascent]", value: String(format: "%.0f", routeAscent))
        appendFormField(named: "route[provider_updated_at]", value: ISO8601DateFormatter().string(from: Date()))
        
        // 5. Append the file data. This is different from a text field.
        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"route[file]\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/vnd.fit\r\n\r\n".data(using: .utf8)!)
        body.append(fitData) // <-- Append the RAW file data, NOT a data URI
        body.append("\r\n".data(using: .utf8)!)
        
        // 6. Append the final boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // 7. Set the built body as the request's httpBody
        request.httpBody = body
        
        print("WahooService: Uploading route to \(url.absoluteString) via multipart/form-data")
        print("WahooService: Route name: \(sanitizedName)")
        print("WahooService: External ID: \(externalId)")
        print("WahooService: File size: \(fitData.count) bytes")
        print("WahooService: Start coordinate: \(startCoordinate.latitude), \(startCoordinate.longitude)")
        print("WahooService: Distance: \(String(format: "%.2f", routeDistanceMeters))m, Ascent: \(String(format: "%.0f", routeAscent))m")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw WahooError.invalidResponse
            }
            
            print("WahooService: Response status: \(httpResponse.statusCode)")
            
            if let responseBody = String(data: data, encoding: .utf8) {
                print("WahooService: Response body: \(responseBody)")
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
                print("WahooService: Upload failed. Status: \(httpResponse.statusCode)")
                print("WahooService: Full response: \(responseBody)")
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let error = json["error"] as? String {
                        throw WahooError.apiErrorWithMessage(statusCode: httpResponse.statusCode, message: error)
                    } else if let errors = json["errors"] as? [[String: Any]] {
                        let errorMessages = errors.compactMap { $0["message"] as? String }
                        throw WahooError.apiErrorWithMessage(statusCode: httpResponse.statusCode, message: errorMessages.joined(separator: ", "))
                    }
                }
                
                throw WahooError.apiError(statusCode: httpResponse.statusCode)
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let routeId = json["id"] as? Int {
                print("WahooService: ✅ Route uploaded successfully! Wahoo Route ID: \(routeId)")
            } else {
                print("WahooService: ✅ Route uploaded successfully!")
            }
            
        } catch let error as WahooError {
            throw error
        } catch {
            print("WahooService: Network error: \(error.localizedDescription)")
            throw WahooError.networkError(error)
        }
    }
    
    // MARK: Update Wahoo Upload to Create Plan
    
    func uploadPlanToWahoo(fitData: Data, planName: String, pacingPlan: PacingPlan) async throws {
        try await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { throw WahooError.notAuthenticated }
        
        // We are making ONE call to /v1/plans using x-www-form-urlencoded
        
        guard let planUrl = URL(string: "\(apiBaseUrl)/v1/plans") else {
            throw WahooError.invalidURL
        }
        
        // Sanitize the name
        let sanitizedName = String(planName.unicodeScalars.filter {
            CharacterSet.alphanumerics.union(.whitespaces).union(.init(charactersIn: "-_")).contains($0)
        })
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(50)
        
        // Create the data URI (as specified in the docs for /v1/routes, which we are mimicking)
        let base64FitData = fitData.base64EncodedString()
        let dataURI = "data:application/vnd.fit;base64,\(base64FitData)"
        
        // Parse metadata
        let parser = RouteParser()
        let startCoordinate: CLLocationCoordinate2D
        var routeDistance: Double = 0
        var routeAscent: Double = 0
        
        if let result = try? parser.parseWithElevation(fitData: fitData) {
            startCoordinate = result.coordinates.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            routeDistance = (result.elevationAnalysis?.elevationProfile.last?.distance ?? 0) / 1000.0 // km
            routeAscent = result.elevationAnalysis?.totalGain ?? 0 // meters
        } else {
            startCoordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        
        let externalId = "rideweatherpro-plan-\(UUID().uuidString)"
        
        var planRequest = URLRequest(url: planUrl)
        planRequest.httpMethod = "POST"
        planRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // SET THE CONTENT TYPE TO FORM URL ENCODED
        planRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Build workout steps. Wahoo's form encoding for nested objects is tricky.
        // It uses "plan[workout_steps][][key]" notation.
        var components = URLComponents()
        var queryItems: [URLQueryItem] = [
            // Plan info
            URLQueryItem(name: "plan[name]", value: String(sanitizedName)),
            URLQueryItem(name: "plan[workout_type_family_id]", value: "0"),
            URLQueryItem(name: "plan[external_id]", value: externalId),
            URLQueryItem(name: "plan[provider_updated_at]", value: ISO8601DateFormatter().string(from: Date())),
            
            // Route file info
            URLQueryItem(name: "plan[file]", value: dataURI),
            URLQueryItem(name: "plan[filename]", value: "\(sanitizedName.replacingOccurrences(of: " ", with: "_")).fit"),
            
            // Optional route metadata
            URLQueryItem(name: "plan[start_lat]", value: String(startCoordinate.latitude)),
            URLQueryItem(name: "plan[start_lng]", value: String(startCoordinate.longitude)),
            URLQueryItem(name: "plan[distance]", value: String(format: "%.2f", routeDistance)),
            URLQueryItem(name: "plan[ascent]", value: String(format: "%.0f", routeAscent)),
            URLQueryItem(name: "plan[description]", value: "Power-based pacing plan from RideWeatherPro")
        ]
        
        
        components.queryItems = queryItems
        planRequest.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        
        print("WahooService: Creating plan with route and \(pacingPlan.segments.count) power segments via x-www-form-urlencoded...")
        
        let (planData, planResponse) = try await URLSession.shared.data(for: planRequest)
        
        if let responseBody = String(data: planData, encoding: .utf8) {
            print("WahooService: Plan response: \(responseBody)")
        }
        
        guard let planHttpResponse = planResponse as? HTTPURLResponse,
              (200...299).contains(planHttpResponse.statusCode) else {
            let errorBody = String(data: planData, encoding: .utf8) ?? "No error body"
            print("WahooService: Plan creation failed: \(errorBody)")
            throw WahooError.apiError(statusCode: (planResponse as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        if let planJson = try? JSONSerialization.jsonObject(with: planData) as? [String: Any],
           let planId = planJson["id"] as? Int {
            print("WahooService: ✅ Workout plan created successfully! Plan ID: \(planId)")
        } else {
            print("WahooService: ✅ Workout plan created successfully! (No ID returned)")
        }
    }
    
    
    
    // MARK: - Error enum
    enum WahooError: LocalizedError {
        case notAuthenticated
        case invalidURL
        case invalidResponse
        case apiError(statusCode: Int)
        case apiErrorWithMessage(statusCode: Int, message: String)
        case noRouteData
        case networkError(Error)
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Not authenticated with Wahoo."
            case .invalidURL:
                return "Invalid API URL."
            case .invalidResponse:
                return "Invalid response from Wahoo."
            case .apiError(let code):
                return "Wahoo API error: \(code)."
            case .apiErrorWithMessage(let code, let message):
                return "Wahoo API error (\(code)): \(message)"
            case .noRouteData:
                return "No GPS route data available for this activity."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            }
        }
    }
}

// (PKCE Extensions)
extension Data {
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    static func random(length: Int) -> Data {
        var data = Data(count: length)
        let result = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, length, $0.baseAddress!)
        }
        if result != errSecSuccess {
            fatalError("Failed to generate random bytes")
        }
        return data
    }
}
