//
//  WahooTokens.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 11/1/25.
//


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
struct WahooTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval
}

struct WahooTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: TimeInterval
    // Wahoo doesn't return athlete data on token exchange
}

struct WahooUser: Decodable {
    let first_name: String
    let last_name: String
}

struct WahooWorkoutSummary: Codable, Identifiable {
    let id: Int
    let name: String
    let distance: Double // meters
    let time: Double // seconds (seems to be moving_time)
    let work: Double // kilojoules
    let start_time: String
    let end_time: String
    
    var startDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: start_time)
    }
    
    var durationFormatted: String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
    
    var distanceKm: Double {
        distance / 1000.0
    }
    
    var distanceMiles: Double {
        distance / 1609.34
    }
}

// MARK: - Wahoo Workout Data (Streams)
struct WahooWorkoutData: Decodable {
    let time: [Double]?         // seconds from start
    let power: [Int]?           // watts
    let heartrate: [Int]?       // bpm
    let cadence: [Int]?         // rpm
    let speed: [Double]?        // m/s
    let distance: [Double]?     // meters (cumulative)
    let altitude: [Double]?     // meters
    let position_lat: [Double]? // degrees
    let position_long: [Double]?// degrees
}

// MARK: - Main Service
@MainActor
class WahooService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    // MARK: - Configuration
    private var wahooConfig: [String: String]?
    private var clientId: String { configValue(forKey: "WahooClientID") ?? "INVALID_CLIENT_ID" }
    private var clientSecret: String { configValue(forKey: "WahooClientSecret") ?? "INVALID_CLIENT_SECRET" }
    
    private let apiBaseUrl = "https://api.wahooligan.com"
    private let redirectUri = "https://faist23.github.io/rideweatherpro-redirect/wahoo-redirect.html"
    private let scope = "user_read workouts_read routes_write offline_data power_zones_read"

    // MARK: - Published State
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String? = nil
    @Published var athleteName: String? = nil

    // MARK: - Internal State
    private var webAuthSession: ASWebAuthenticationSession?
    private var currentPkceVerifier: String?
    private var currentTokens: WahooTokens? {
        didSet {
            isAuthenticated = currentTokens != nil
            saveTokensToKeychain()
        }
    }
    private let athleteNameKey = "wahoo_athlete_name"

    override init() {
        super.init()
        loadConfig()
        loadTokensFromKeychain()
        loadAthleteNameFromKeychain()
    }

    // MARK: - Config Loading
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

    // MARK: - Authentication (PKCE Flow)
    func authenticate() {
        guard wahooConfig != nil,
              clientId != "INVALID_CLIENT_ID" else {
            errorMessage = "Invalid Wahoo configuration."
            return
        }
        
        // 1. Generate PKCE Verifier and Challenge
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

    // MARK: - Handle Redirect
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

    // MARK: - Exchange Code -> Tokens
    private func exchangeToken(code: String, pkceVerifier: String) {
        guard let tokenURL = URL(string: "\(apiBaseUrl)/oauth/token") else { return }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret), // Required even for PKCE
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "code_verifier", value: pkceVerifier) // The crucial PKCE part
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
                    let tokenResponse = try JSONDecoder().decode(WahooTokenResponse.self, from: data)
                    self.currentTokens = WahooTokens(
                        accessToken: tokenResponse.access_token,
                        refreshToken: tokenResponse.refresh_token,
                        expiresAt: Date().timeIntervalSince1970 + tokenResponse.expires_in
                    )
                    self.errorMessage = nil
                    // After getting tokens, fetch user's name
                    await self.fetchUserName()
                } catch {
                    self.errorMessage = "Token decoding failed."
                }
            }
        }.resume()
    }

    // MARK: - Token Refresh
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
                    let tokenResponse = try JSONDecoder().decode(WahooTokenResponse.self, from: data)
                    self.currentTokens = WahooTokens(
                        accessToken: tokenResponse.access_token,
                        refreshToken: tokenResponse.refresh_token,
                        expiresAt: Date().timeIntervalSince1970 + tokenResponse.expires_in
                    )
                    self.errorMessage = nil
                    completion(.success(()))
                } catch {
                    self.disconnect(); completion(.failure(error))
                }
            }
        }.resume()
    }
    
    // MARK: - Disconnect
    func disconnect() {
        currentTokens = nil
        athleteName = nil
        deleteAthleteNameFromKeychain()
        isAuthenticated = false
    }
    
    // MARK: - Keychain Persistence
    private let keychainService = Bundle.main.bundleIdentifier ?? "com.rideweatherpro.wahoo"
    private let keychainAccount = "wahooUserTokensV1"

    private func saveTokensToKeychain() {
        guard let tokens = currentTokens else {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainAccount]
            SecItemDelete(query as CFDictionary)
            return
        }
        do {
            let data = try JSONEncoder().encode(tokens)
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
                self.currentTokens = try JSONDecoder().decode(WahooTokens.self, from: data)
                if Date().timeIntervalSince1970 >= (currentTokens?.expiresAt ?? 0) - 3600 {
                    refreshTokenIfNeeded { _ in }
                }
            } catch {
                self.currentTokens = nil; saveTokensToKeychain()
            }
        }
    }

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
    
    // MARK: - Presentation Anchor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }
            .first ?? UIWindow()
    }
    
    // MARK: - PKCE Helper
    private func generatePKCE() -> (verifier: String, challenge: String) {
        let verifier = Data.random(length: 32).base64URLEncodedString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        return (verifier, challenge)
    }
    
    // MARK: - API Helper
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
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            
            let user = try JSONDecoder().decode(WahooUser.self, from: data)
            let name = "\(user.first_name) \(user.last_name)"
            self.athleteName = name
            saveAthleteNameToKeychain(name)
        } catch {
            print("WahooService: Could not fetch user name: \(error.localizedDescription)")
        }
    }

    func fetchRecentWorkouts() async throws -> [WahooWorkoutSummary] {
        try await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { throw WahooError.notAuthenticated }
        
        var components = URLComponents(string: "\(apiBaseUrl)/v1/workouts")!
        components.queryItems = [
            URLQueryItem(name: "page", value: "0"),
            URLQueryItem(name: "per_page", value: "50"),
            URLQueryItem(name: "sort", value: "-starts") // Most recent first
        ]
        
        guard let url = components.url else { throw WahooError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WahooError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        
        // Wahoo nests the workouts in a "workouts" key
        let decoder = JSONDecoder()
        let result = try decoder.decode([String: [WahooWorkoutSummary]].self, from: data)
        return result["workouts"] ?? []
    }
    
    func fetchWorkoutData(workoutId: Int) async throws -> WahooWorkoutData {
        try await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { throw WahooError.notAuthenticated }
        
        guard let url = URL(string: "\(apiBaseUrl)/v1/workouts/\(workoutId)/data") else {
            throw WahooError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WahooError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        
        return try JSONDecoder().decode(WahooWorkoutData.self, from: data)
    }
    
    func uploadRouteToWahoo(fitData: Data, routeName: String) async throws {
        try await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { throw WahooError.notAuthenticated }
        
        guard let url = URL(string: "\(apiBaseUrl)/v1/routes") else {
            throw WahooError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        // Create multipart/form-data body
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add route_name field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"name\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(routeName)\r\n".data(using: .utf8)!)
        
        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(routeName).fit\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fitData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add final boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WahooError.invalidResponse
        }

        // Wahoo returns 201 Created on success
        guard httpResponse.statusCode == 201 else {
            print("WahooService: Upload failed. Status: \(httpResponse.statusCode). Response: \(String(data: data, encoding: .utf8) ?? "N/A")")
            throw WahooError.apiError(statusCode: httpResponse.statusCode)
        }
        
        print("WahooService: Route uploaded successfully!")
    }

    // MARK: - Error Types
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

// MARK: - PKCE Helper Extensions
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