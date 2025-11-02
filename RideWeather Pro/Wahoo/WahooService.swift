//
//  WahooService.swift
//  RideWeather Pro
//

import Foundation
import AuthenticationServices
import Combine
import UIKit
import CryptoKit

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
    let firstName: String?
    let lastName: String?
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
    private let scope = "user_read workouts_read routes_write offline_data power_zones_read"
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

    // --- FIX: Add .keyDecodingStrategy = .convertFromSnakeCase ---
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

    // --- FIX: Add .keyDecodingStrategy = .convertFromSnakeCase ---
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
    
    // (Disconnect is correct)
    func disconnect() {
        currentTokens = nil
        athleteName = nil
        deleteAthleteNameFromKeychain()
        isAuthenticated = false
    }
    
    // --- FIX: Keychain functions must use a *default* decoder/encoder ---
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
    
    // --- FIX: Add .keyDecodingStrategy = .convertFromSnakeCase ---
    func fetchUserName() async {
        try? await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { return }
        
        guard let url = URL(string: "\(apiBaseUrl)/v1/user") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase // <-- FIX
            let user = try decoder.decode(WahooUser.self, from: data)
            
            let firstName = user.firstName ?? ""
            let lastName = user.lastName ?? ""
            let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            let finalName = name.isEmpty ? "Wahoo User" : name
            
            self.athleteName = finalName
            saveAthleteNameToKeychain(finalName)
            
        } catch {
            print("WahooService: Could not fetch user name: \(error.localizedDescription)")
        }
    }

    // Fetch workouts list
    func fetchRecentWorkouts() async throws -> [WahooWorkoutSummary] {
/*        let url = URL(string: "https://api.wahooligan.com/v1/workouts?page=1&per_page=50")!
        var request = URLRequest(url: url)
        // Add your authentication headers here...

        guard let token = currentTokens?.accessToken else { throw WahooError.notAuthenticated }
        print("WahooService: Using token:", token)*/
        try await refreshTokenIfNeededAsync()
         guard let token = currentTokens?.accessToken else { throw WahooError.notAuthenticated }
         var components = URLComponents(string: "\(apiBaseUrl)/v1/workouts")!
         components.queryItems = [
             URLQueryItem(name: "page", value: "0"),
             URLQueryItem(name: "per_page", value: "50"),
             URLQueryItem(name: "sort", value: "-starts")
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
            return response.workouts
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
    
    // (uploadRouteToWahoo)
    func uploadRouteToWahoo(fitData: Data, routeName: String) async throws {
        try await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { throw WahooError.notAuthenticated }
        
        guard let url = URL(string: "\(apiBaseUrl)/v1/routes") else {
            throw WahooError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"name\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(routeName)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(routeName).fit\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fitData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WahooError.invalidResponse
        }
        guard httpResponse.statusCode == 201 else {
            print("WahooService: Upload failed. Status: \(httpResponse.statusCode). Response: \(String(data: data, encoding: .utf8) ?? "N/A")")
            throw WahooError.apiError(statusCode: httpResponse.statusCode)
        }
        print("WahooService: Route uploaded successfully!")
    }

    // (Error enum)
    enum WahooError: LocalizedError {
        case notAuthenticated
        case invalidURL
        case invalidResponse
        case apiError(statusCode: Int)
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Not authenticated with Wahoo."
            case .invalidURL: return "Invalid API URL."
            case .invalidResponse: return "Invalid response from Wahoo."
            case .apiError(let code): return "Wahoo API error: \(code)."
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
/*
extension WahooWorkoutSummary {
    var distanceKm: Double {
        Double(workoutSummary?.distanceAccum ?? "0")! / 1000.0
    }
    var distanceMiles: Double {
        Double(workoutSummary?.distanceAccum ?? "0")! / 1609.34
    }
}*/
