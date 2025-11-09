//
//  StravaService.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 10/21/25.
//

import Foundation
import AuthenticationServices
import Combine
import UIKit
import CoreLocation

// MARK: - Data Models
struct StravaTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval
}

struct StravaTokenResponse: Decodable {
    let token_type: String
    let expires_at: TimeInterval
    let expires_in: Int
    let refresh_token: String
    let access_token: String
    let athlete: StravaAthlete?
}

struct StravaAthlete: Codable {
    let id: Int?  // ✅ ADD THIS
    let firstname: String?
    let lastname: String?
}

struct StravaDetailedAthlete: Codable {
    let id: Int
    let firstname: String?
    let lastname: String?
    let weight: Double? // Weight is in kilograms
}

// MARK: - Strava Activity Models
struct StravaActivity: Codable, Identifiable {
    let id: Int
    let name: String
    let distance: Double // meters
    let moving_time: Int // seconds
    let elapsed_time: Int // seconds
    let total_elevation_gain: Double // meters
    let type: String
    let start_date: String
    let start_date_local: String
    let timezone: String
    let average_speed: Double? // m/s
    let max_speed: Double? // m/s
    let average_watts: Double?
    let kilojoules: Double?
    let device_watts: Bool?
    let has_heartrate: Bool
    let average_heartrate: Double?
    let max_heartrate: Double?
    let suffer_score: Double?
    let trainer: Bool?
    
    var startDate: Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: start_date)
    }
    
    var distanceKm: Double {
        distance / 1000.0
    }
    
    var distanceMiles: Double {
        distance / 1609.34
    }
    
    var durationFormatted: String {
        let hours = moving_time / 3600
        let minutes = (moving_time % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    // 🔥 NEW: Stopped time helper
    var stoppedTime: Int {
        return elapsed_time - moving_time
    }
    
    // 🔥 NEW: Has significant stops?
    var hasSignificantStops: Bool {
        return stoppedTime > 60  // More than 1 minute
    }
}

// MARK: - Strava Streams Models (add after StravaActivityDetail)

struct StravaStreams: Codable {
    let time: StreamData?
    let distance: StreamData?
    let latlng: LatLngStreamData?
    let altitude: StreamData?
    let velocity_smooth: StreamData?
    let heartrate: StreamData?
    let cadence: StreamData?
    let watts: StreamData?
    let temp: StreamData?
    let moving: BoolStreamData?  // ✅ CHANGED from StreamData to BoolStreamData
    let grade_smooth: StreamData?
    
    struct StreamData: Codable {
        let data: [Double]
        let series_type: String
        let original_size: Int
        let resolution: String
    }
    
    struct BoolStreamData: Codable {  // ✅ NEW type for boolean streams
        let data: [Bool]
        let series_type: String
        let original_size: Int
        let resolution: String
    }
    
    struct LatLngStreamData: Codable {
        let data: [[Double]]  // [latitude, longitude] pairs
        let series_type: String
        let original_size: Int
        let resolution: String
    }
}

// MARK: - Main Service
@MainActor
class StravaService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    
    // MARK: - Configuration
    private var stravaConfig: [String: String]?
    private var clientId: String { configValue(forKey: "StravaClientID") ?? "INVALID_CLIENT_ID" }
    private var clientSecret: String { configValue(forKey: "StravaClientSecret") ?? "INVALID_CLIENT_SECRET" }
    
    private let redirectUri = "https://faist23.github.io/rideweatherpro-redirect/strava-redirect.html"
    private let scope = "activity:read_all,profile:read_all,read_all"
    
    // MARK: - Published State
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String? = nil
    @Published var athleteName: String? = nil
    
    // MARK: - Internal State
    private var webAuthSession: ASWebAuthenticationSession?
    internal var currentTokens: StravaTokens? {
        didSet {
            isAuthenticated = currentTokens != nil
            saveTokensToKeychain()
        }
    }
    
    // Separate Keychain slot for athlete name (so we persist connection state even if tokens expire)
    private let athleteNameKey = "strava_athlete_name"
    private let lastWeightSyncKey = "strava_last_weight_sync"
    
    override init() {
        super.init()
        loadConfig()
        loadTokensFromKeychain()
        loadAthleteNameFromKeychain() // ✅ restore athlete name
    }
    
    /// Automatically syncs athlete weight from Strava if the setting is enabled and it hasn't been synced today.
    /// - Parameter settings: The app's current settings.
    /// - Returns: The new weight in Kilograms if sync was successful, otherwise nil.
    func autoSyncWeightIfNeeded(settings: AppSettings) async -> Double? {
        // 1. Check if user wants auto-sync and is authenticated
        guard settings.autoSyncWeightFromStrava, isAuthenticated else {
            return nil
        }
        
        // 2. Check if we've already synced today
        if let lastSync = UserDefaults.standard.object(forKey: lastWeightSyncKey) as? Date {
            if Calendar.current.isDateInToday(lastSync) {
                print("StravaService: Weight sync already performed today.")
                return nil
            }
        }
        
        // 3. Perform the sync
        print("StravaService: Performing daily auto-sync for weight...")
        do {
            if let weightInKg = try await fetchAthleteWeight(), weightInKg > 0 {
                // 4. Update UserDefaults with the sync time
                UserDefaults.standard.set(Date(), forKey: lastWeightSyncKey)
                print("StravaService: Auto-sync successful. New weight: \(weightInKg) kg")
                return weightInKg
            } else {
                print("StravaService: Auto-sync: No weight found on Strava profile.")
                return nil
            }
        } catch {
            print("StravaService: Auto-sync for weight failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Config Loading
    private func loadConfig() {
        guard let path = Bundle.main.path(forResource: "StravaConfig", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            print("🚨 StravaService FATAL ERROR: StravaConfig.plist missing or malformed.")
            errorMessage = "Critical configuration error. Strava disabled."
            stravaConfig = nil
            return
        }
        stravaConfig = dict
        print("StravaService: Configuration loaded.")
    }
    
    private func configValue(forKey key: String) -> String? {
        return stravaConfig?[key]
    }
    
    // MARK: - Authentication
    func authenticate() {
        guard stravaConfig != nil,
              clientId != "INVALID_CLIENT_ID",
              clientSecret != "INVALID_CLIENT_SECRET" else {
            errorMessage = "Invalid Strava configuration."
            print("StravaService Error: Config invalid.")
            return
        }
        
        print("StravaService: Starting authentication...")
        var components = URLComponents(string: "https://www.strava.com/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "force"),
            URLQueryItem(name: "scope", value: scope)
        ]
        
        guard let authURL = components.url else { return }
        
        webAuthSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "rideweatherpro"
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            
            if let error = error {
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    print("StravaService: Login canceled.")
                } else {
                    print("StravaService Error: \(error.localizedDescription)")
                    self.errorMessage = error.localizedDescription
                }
                return
            }
            
            guard let url = callbackURL else { return }
            print("StravaService: Callback received: \(url)")
            self.handleRedirect(url: url)
        }
        
        webAuthSession?.presentationContextProvider = self
        webAuthSession?.prefersEphemeralWebBrowserSession = true
        print("StravaService: Launching auth session...")
        _ = webAuthSession?.start()
    }
    
    // MARK: - Handle Redirect
    func handleRedirect(url: URL) {
        print("StravaService: Handling redirect...")
        guard url.scheme == "rideweatherpro",
              url.host == "strava-auth",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            print("StravaService: Invalid redirect URL.")
            return
        }
        
        print("StravaService: Received authorization code: \(code)")
        exchangeToken(code: code)
    }
    
    // MARK: - Exchange Code → Tokens
    private func exchangeToken(code: String) {
        print("StravaService: Exchanging code for tokens...")
        
        guard let tokenURL = URL(string: "https://www.strava.com/oauth/token") else { return }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "grant_type", value: "authorization_code")
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            Task { @MainActor in
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    print("StravaService Error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    print("StravaService: Empty response.")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("StravaService: Token exchange response: \(httpResponse.statusCode)")
                }
                
                do {
                    let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)
                    self.currentTokens = StravaTokens(
                        accessToken: tokenResponse.access_token,
                        refreshToken: tokenResponse.refresh_token,
                        expiresAt: tokenResponse.expires_at
                    )
                    // ✅ CRITICAL: Store athlete ID
                    if let athleteId = tokenResponse.athlete?.id {
                        UserDefaults.standard.set(athleteId, forKey: "strava_athlete_id")
                        print("StravaService: ✅ Stored athlete ID: \(athleteId)")
                    } else {
                        print("StravaService: ⚠️ WARNING - No athlete ID in token response!")
                    }

                     // Store athlete name and update UI
                     let name = tokenResponse.athlete?.firstname ?? "Strava User"
                     self.athleteName = name
                     self.saveAthleteNameToKeychain(name)

                     print("StravaService: Authenticated as \(name).")
                     self.errorMessage = nil
                 } catch {
                     print("StravaService Error: \(error.localizedDescription)")
                     self.errorMessage = "Token decoding failed."
                 }
             }
         }.resume()
     }
    
    // MARK: - Token Refresh
    /// Checks if the access token needs refreshing and performs the refresh if necessary.
    func refreshTokenIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tokens = currentTokens else {
            let error = NSError(domain: "StravaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
            print("StravaService: No tokens to refresh.")
            completion(.failure(error))
            return
        }
        
        // Check if token expires within the next hour (3600 seconds) for a safety margin
        let needsRefresh = Date().timeIntervalSince1970 >= tokens.expiresAt - 3600
        
        if !needsRefresh {
            print("StravaService: Access token still valid (expires at \(Date(timeIntervalSince1970: tokens.expiresAt))).")
            completion(.success(()))
            return
        }
        
        print("StravaService: Access token expired or nearing expiry. Refreshing...")
        // Ensure config is available
        guard stravaConfig != nil,
              clientId != "INVALID_CLIENT_ID",
              clientSecret != "INVALID_CLIENT_SECRET" else {
            errorMessage = "Strava integration is not configured correctly."
            print("StravaService Error: Attempted token refresh without valid config.")
            let error = NSError(domain: "StravaService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Configuration Error"])
            completion(.failure(error))
            return
        }
        
        guard let tokenURL = URL(string: "https://www.strava.com/oauth/token") else {
            let error = NSError(domain: "StravaService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid token URL"])
            completion(.failure(error))
            return
        }
        
        // Prepare the refresh request
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret), // Use loaded secret
            URLQueryItem(name: "refresh_token", value: tokens.refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token") // Specify refresh grant
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        
        // Perform the network request
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // Capture response INSIDE the Task block
            Task { @MainActor in // Switch back to main thread
                // Capture httpResponse here so it's available inside this Task
                let validHttpResponse = response as? HTTPURLResponse // Use this name consistently now
                // --- END CAPTURE ---
                
                if let error = error {
                    self.errorMessage = "Token refresh network failed: \(error.localizedDescription)"
                    print("StravaService Error: \(self.errorMessage!)")
                    self.disconnect()
                    completion(.failure(error))
                    return
                }
                
                // Use the captured validHttpResponse variable
                guard let validHttpResponse = validHttpResponse, let data = data else { // Make sure to use the captured variable
                    self.errorMessage = "Invalid response during token refresh."
                    print("StravaService Error: \(self.errorMessage!)")
                    self.disconnect()
                    let error = NSError(domain: "StravaService", code: validHttpResponse?.statusCode ?? -4, userInfo: [NSLocalizedDescriptionKey: "Invalid refresh response"]) // Use optional chaining here too
                    completion(.failure(error))
                    return
                }
                
                if let responseString = String(data: data, encoding: .utf8) {
                    // Use the captured validHttpResponse.statusCode
                    print("StravaService: Refresh Token Response (\(validHttpResponse.statusCode)): \(responseString)")
                }
                
                // --- FIX IS HERE (Line 398 area) ---
                // Use the captured validHttpResponse.statusCode consistently
                guard validHttpResponse.statusCode == 200 else {
                    self.errorMessage = "Token refresh failed: Status \(validHttpResponse.statusCode)" // Use captured variable
                    print("StravaService Error: \(self.errorMessage!) - Refresh token might be invalid.")
                    self.disconnect()
                    // Use captured variable's statusCode
                    let error = NSError(domain: "StravaService", code: validHttpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Refresh token failed or revoked"])
                    completion(.failure(error))
                    return
                }
                
                // --- END UPDATED GUARD ---
                
                if let responseString = String(data: data, encoding: .utf8) {
                    // --- UPDATED LOGGING --- Use the captured validHttpResponse.statusCode
                    print("StravaService: Refresh Token Response (\(validHttpResponse.statusCode)): \(responseString)")
                }
                
                // --- UPDATED GUARD --- Use the captured validHttpResponse.statusCode
                guard validHttpResponse.statusCode == 200 else {
                    self.errorMessage = "Token refresh failed: Status \(validHttpResponse.statusCode)"
                    print("StravaService Error: \(self.errorMessage!) - Refresh token might be invalid.")
                    self.disconnect() // Assume refresh token is bad, force re-auth
                    // --- UPDATED ERROR --- Use the captured validHttpResponse.statusCode
                    let error = NSError(domain: "StravaService", code: validHttpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Refresh token failed or revoked"])
                    completion(.failure(error))
                    return
                }
                // Decode the new tokens
                do {
                    let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)
                    print("StravaService: Tokens refreshed successfully.")
                    // Update stored tokens with the new ones
                    self.currentTokens = StravaTokens(
                        accessToken: tokenResponse.access_token,
                        refreshToken: tokenResponse.refresh_token, // Update in case it changed
                        expiresAt: tokenResponse.expires_at
                    )
                    self.errorMessage = nil // Clear error on success
                    completion(.success(())) // Signal success
                } catch {
                    self.errorMessage = "Failed to decode refreshed token response: \(error.localizedDescription)"
                    print("StravaService Error: \(self.errorMessage!)")
                    self.disconnect() // Disconnect if decoding fails
                    completion(.failure(error))
                }
            }
        }
        task.resume() // Start the refresh request
    }
    
    
    // MARK: - Disconnect
    func disconnect() {
        currentTokens = nil
        athleteName = nil
        deleteAthleteNameFromKeychain()
        isAuthenticated = false
        print("StravaService: User disconnected.")
    }
    
    // MARK: - Presentation Anchor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
        
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first {
            return window
        }
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return UIWindow(windowScene: windowScene)
        }
        
        fatalError("Unable to find window scene")
    }
    
    // MARK: - Athlete Name Persistence
    private func saveAthleteNameToKeychain(_ name: String) {
        let data = Data(name.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: athleteNameKey,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
        print("StravaService: Athlete name saved.")
    }
    
    private func loadAthleteNameFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: athleteNameKey,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var ref: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess,
           let data = ref as? Data,
           let name = String(data: data, encoding: .utf8) {
            athleteName = name
            print("StravaService: Restored athlete name: \(name)")
        }
    }
    
    private func deleteAthleteNameFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: athleteNameKey
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    /// Fetches the authenticated athlete's weight from Strava.
    /// - Returns: Weight in kilograms, or nil if not set.
    func fetchAthleteWeight() async throws -> Double? {
        let athlete = try await fetchDetailedAthlete()
        return athlete.weight
    }
    
    /// ADD THIS HELPER FUNCTION (or make fetchAthleteWeight do all this)
    /// Fetches the authenticated athlete's detailed profile
    private func fetchDetailedAthlete() async throws -> StravaDetailedAthlete {
        await refreshTokenIfNeededAsync()
        
        guard let accessToken = currentTokens?.accessToken else {
            throw StravaError.notAuthenticated
        }
        
        guard let url = URL(string: "https://www.strava.com/api/v3/athlete") else {
            throw StravaError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StravaError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        // Strava returns weight in kilograms
        return try JSONDecoder().decode(StravaDetailedAthlete.self, from: data)
    }
    
    // MARK: - Token Persistence (Using Keychain)
    
    // Define unique keys for Keychain access
    private let keychainService = Bundle.main.bundleIdentifier ?? "com.yourapp.default.strava" // Use app's bundle ID
    private let keychainAccount = "stravaUserTokensV1" // Add a version if structure changes
    
    /// Saves the current Strava tokens securely to the Keychain.
    private func saveTokensToKeychain() {
        // If tokens are nil (user disconnected), delete from Keychain
        guard let tokens = currentTokens else {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecSuccess || status == errSecItemNotFound {
                print("StravaService: Deleted tokens from Keychain.")
            } else {
                // Log error, but don't block UI for deletion failure
                print("StravaService: Error deleting tokens from Keychain (status: \(status)).")
            }
            return
        }
        
        // Encode the token struct into Data
        do {
            let data = try JSONEncoder().encode(tokens)
            
            // Prepare Keychain query for saving/updating
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword, // Store as generic password
                kSecAttrService as String: keychainService,     // Differentiates your app's data
                kSecAttrAccount as String: keychainAccount,     // Specific key for these tokens
                kSecValueData as String: data,                  // The encoded token data
                // Recommended security: only accessible when device is unlocked
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            
            // Delete any existing item first to ensure an update works reliably
            SecItemDelete(query as CFDictionary) // Ignore error, might not exist yet
            
            // Add the new item to the Keychain
            let status = SecItemAdd(query as CFDictionary, nil)
            if status == errSecSuccess {
                print("StravaService: Tokens saved securely to Keychain.")
            } else {
                print("StravaService: Error saving tokens to Keychain (status: \(status)).")
                Task { @MainActor in self.errorMessage = "Failed to save Strava connection." }
            }
        } catch {
            print("StravaService: Error encoding tokens for Keychain: \(error)")
            Task { @MainActor in self.errorMessage = "Failed to prepare Strava connection for saving." }
        }
    }
    /// Loads Strava tokens from the Keychain on app launch.
    private func loadTokensFromKeychain() {
        // Prepare Keychain query for retrieving data
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: kCFBooleanTrue!,   // Request the actual data
            kSecMatchLimit as String: kSecMatchLimitOne // We only expect one item
        ]
        
        var item: CFTypeRef? // Variable to hold the retrieved data
        // Attempt to copy the matching item from Keychain
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        // Check if item was found successfully
        guard status == errSecSuccess, let data = item as? Data else {
            if status == errSecItemNotFound {
                print("StravaService: No tokens found in Keychain.")
            } else {
                // Log other potential Keychain errors
                print("StravaService: Error loading tokens from Keychain (status: \(status)).")
            }
            self.currentTokens = nil // Ensure internal state is nil if loading fails
            return
        }
        
        // Decode the retrieved data back into StravaTokens struct
        do {
            let decodedTokens = try JSONDecoder().decode(StravaTokens.self, from: data)
            // Assign to internal state (triggers didSet and saves again if needed, also updates isAuthenticated)
            self.currentTokens = decodedTokens
            print("StravaService: Tokens loaded securely from Keychain.")
            
            // Immediately check if the loaded token needs refreshing
            Task { @MainActor in
                // Check if expired or expires within the next hour
                if Date().timeIntervalSince1970 >= (currentTokens?.expiresAt ?? 0) - 3600 {
                    print("StravaService: Loaded token needs refresh.")
                    // Attempt refresh silently in the background
                    refreshTokenIfNeeded { result in
                        if case .failure(let error) = result {
                            print("StravaService: Auto-refresh failed on load: \(error.localizedDescription)")
                            // Error message is set within refreshTokenIfNeeded if it fails
                        }
                    }
                }
            }
        } catch {
            print("StravaService: Error decoding tokens from Keychain: \(error). Removing invalid data.")
            self.currentTokens = nil // Clear invalid tokens from memory
            // Attempt to delete the invalid item from keychain to prevent future errors
            saveTokensToKeychain() // Calling save with nil currentTokens deletes the item
        }
    }
    
    // MARK: - API Methods
    
    /// Fetches recent activities from Strava with pagination
    func fetchRecentActivities(page: Int = 1, perPage: Int = 100) async throws -> [StravaActivity] {
        // Ensure we have a valid token
        await refreshTokenIfNeededAsync()
        
        guard let accessToken = currentTokens?.accessToken else {
            throw StravaError.notAuthenticated
        }
        
        var components = URLComponents(string: "https://www.strava.com/api/v3/athlete/activities")!
        components.queryItems = [
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "page", value: String(page))
        ]
        
        guard let url = components.url else {
            throw StravaError.invalidURL
        }
        
        print("StravaService: Fetching activities page \(page) (\(perPage) per page)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw StravaError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let activities = try JSONDecoder().decode([StravaActivity].self, from: data)
        
        // ✅ DON'T FILTER HERE - return all activities and let the caller decide
        print("StravaService: Fetched \(activities.count) total activities on page \(page)")
        
        return activities
    }
    
    // MARK: - Helper Methods
    
    // Helper to get current athlete ID (you'll need to store this during auth)
    private func getCurrentAthleteId() -> Int {
        // You can store this in UserDefaults during authentication
        return UserDefaults.standard.integer(forKey: "strava_athlete_id")
    }

    // Update the token response to store athlete ID
    // In exchangeToken and refreshTokenIfNeeded, add:
    // UserDefaults.standard.set(tokenResponse.athlete?.id ?? 0, forKey: "strava_athlete_id")

    private func refreshTokenIfNeededAsync() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            refreshTokenIfNeeded { result in
                // We'll ignore the result here since we handle auth errors elsewhere
                continuation.resume()
            }
        }
    }
    
    /// Fetches activity streams (second-by-second data) from Strava
    func fetchActivityStreams(activityId: Int) async throws -> StravaStreams {
        await refreshTokenIfNeededAsync()
        
        guard let accessToken = currentTokens?.accessToken else {
            throw StravaError.notAuthenticated
        }
        
        // Request all available streams
        let streamTypes = ["time", "distance", "latlng", "altitude", "velocity_smooth",
                           "heartrate", "cadence", "watts", "temp", "moving", "grade_smooth"]
        
        var components = URLComponents(string: "https://www.strava.com/api/v3/activities/\(activityId)/streams")!
        components.queryItems = [
            URLQueryItem(name: "keys", value: streamTypes.joined(separator: ",")),
            URLQueryItem(name: "key_by_type", value: "true")
        ]
        
        guard let url = components.url else {
            throw StravaError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw StravaError.streamsNotAvailable
            }
            throw StravaError.apiError(statusCode: httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(StravaStreams.self, from: data)
    }
    
    
    /// Fetches the athlete's saved routes
    func fetchRoutes(limit: Int = 30) async throws -> [StravaRoute] {
        await refreshTokenIfNeededAsync()
        
        guard let accessToken = currentTokens?.accessToken else {
            print("StravaService Error: No access token available")
            throw StravaError.notAuthenticated
        }

        // Get athlete ID with detailed logging
        let athleteId = UserDefaults.standard.integer(forKey: "strava_athlete_id")
        print("StravaService: Attempting to fetch routes for athlete ID: \(athleteId)")
        
        guard athleteId > 0 else {
            print("StravaService Error: Invalid athlete ID (\(athleteId)). User needs to re-authenticate.")
            throw StravaError.notAuthenticated
        }

        var components = URLComponents(string: "https://www.strava.com/api/v3/athletes/\(athleteId)/routes")!
        components.queryItems = [
            URLQueryItem(name: "per_page", value: String(limit)),
            URLQueryItem(name: "page", value: "1")
        ]
        
        guard let url = components.url else {
            throw StravaError.invalidURL
        }
        
        print("StravaService: Fetching routes from: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaError.invalidResponse
        }
        
        print("StravaService: Routes API response status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 401 {
            print("StravaService Error: Unauthorized - token may be expired")
            throw StravaError.notAuthenticated
        }
        
        guard httpResponse.statusCode == 200 else {
            if let responseString = String(data: data, encoding: .utf8) {
                print("StravaService Error Response: \(responseString)")
            }
            throw StravaError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let routes = try JSONDecoder().decode([StravaRoute].self, from: data)
        let cyclingRoutes = routes.filter { $0.type == 1 }
        print("StravaService: Successfully fetched \(cyclingRoutes.count) cycling routes (out of \(routes.count) total)")
        
        return cyclingRoutes
    }
    
    /// Fetches detailed route information including GPS data
    func fetchRouteDetail(routeId: Int) async throws -> StravaRouteDetail {
        await refreshTokenIfNeededAsync()
        
        guard let accessToken = currentTokens?.accessToken else {
            throw StravaError.notAuthenticated
        }
        
        guard let url = URL(string: "https://www.strava.com/api/v3/routes/\(routeId)") else {
            throw StravaError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw StravaError.apiError(statusCode: httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(StravaRouteDetail.self, from: data)
    }
    
    /// Extracts GPS route from a Strava Route (planned route)
    func extractRouteFromStravaRoute(routeId: Int) async throws -> [CLLocationCoordinate2D] {
        print("StravaService: Fetching route detail for route \(routeId)")
        
        // Fetch route detail
        let routeDetail = try await fetchRouteDetail(routeId: routeId)
        
        guard let map = routeDetail.map,
              let polyline = map.polyline ?? map.summary_polyline else {
            throw StravaError.noRouteData
        }
        
        print("StravaService: Decoding polyline for route")
        
        // Decode polyline to coordinates
        let coordinates = decodePolyline(polyline)
        
        guard !coordinates.isEmpty else {
            throw StravaError.noRouteData
        }
        
        print("StravaService: Extracted \(coordinates.count) GPS points from route")
        return coordinates
    }
    
    /// Extracts GPS route from a Strava activity for weather analysis
    func extractRouteFromStravaRoute(routeId: Int) async throws -> (coordinates: [CLLocationCoordinate2D], totalDistanceMeters: Double) { // ✅ CHANGED
            print("StravaService: Fetching route detail for route \(routeId)")
            
            // Fetch route detail
            let routeDetail = try await fetchRouteDetail(routeId: routeId)
            
            // ✅ ADDED: Get the authoritative distance
            let totalDistance = routeDetail.distance // This is in meters
            
            guard let map = routeDetail.map,
                  let polyline = map.polyline ?? map.summary_polyline else {
                throw StravaError.noRouteData
            }
            
            print("StravaService: Decoding polyline for route")
            
            // Decode polyline to coordinates
            let coordinates = decodePolyline(polyline)
            
            guard !coordinates.isEmpty else {
                throw StravaError.noRouteData
            }
            
            print("StravaService: Extracted \(coordinates.count) GPS points from route")
            // ✅ CHANGED: Return both coordinates and distance
            return (coordinates: coordinates, totalDistanceMeters: totalDistance)
        }
        
        /// Extracts GPS route from a Strava activity for weather analysis
    func extractRouteFromActivity(activityId: Int) async throws -> (coordinates: [CLLocationCoordinate2D], totalDistanceMeters: Double) {
            await refreshTokenIfNeededAsync()
            
            guard let accessToken = currentTokens?.accessToken else {
                throw StravaError.notAuthenticated
            }
            
            // ✅ CHANGED: Request "time", "distance", "latlng", AND "moving".
            // --- "watts" has been removed ---
            let streamTypes = ["time", "distance", "latlng", "moving"]
            
            var components = URLComponents(string: "https://www.strava.com/api/v3/activities/\(activityId)/streams")!
            components.queryItems = [
                URLQueryItem(name: "keys", value: streamTypes.joined(separator: ",")),
                URLQueryItem(name: "key_by_type", value: "true")
            ]
            
            guard let url = components.url else {
                throw StravaError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw StravaError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw StravaError.apiError(statusCode: httpResponse.statusCode)
            }
            
            let streams = try JSONDecoder().decode(StravaStreams.self, from: data)

            // ✅ ALL LOGIC BELOW IS REVISED
            
            guard let timeData = streams.time?.data, !timeData.isEmpty,
                  let latlngData = streams.latlng?.data,
                  let distanceData = streams.distance?.data else {
                // We need these three streams at a minimum.
                throw StravaError.noRouteData
            }
            
            // Get the moving stream, or default to all true if it's not present
            let movingData = streams.moving?.data

            var filteredCoordinates: [CLLocationCoordinate2D] = []
            var filteredDistances: [Double] = []
            
            for i in 0..<timeData.count {
                // Check 1: Check if moving. If movingData is nil, assume true.
                let isMoving = movingData?[safe: i] ?? true
                
                if !isMoving {
                    continue // Skip this data point if it's marked as "stopped"
                }
                
                // ✅ REMOVED: The check for `powerData` is gone.
                
                // Now we know it's a "moving" point, get its data
                guard let latlng = latlngData[safe: i], latlng.count == 2,
                      let distance = distanceData[safe: i] else {
                    continue // Skip if data is misaligned
                }
                
                let lat = latlng[0]
                let lon = latlng[1]

                // Validate coordinates
                guard abs(lat) <= 90, abs(lon) <= 180, lat != 0, lon != 0 else {
                    continue
                }
                
                filteredCoordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                filteredDistances.append(distance)
            }

            // Now, get the last distance from the *filtered* list
            guard let totalDistance = filteredDistances.last, !filteredCoordinates.isEmpty else {
                // This would mean the entire activity was marked "stopped" or had no GPS
                throw StravaError.noRouteData
            }
            
            print("StravaService: Extracted \(filteredCoordinates.count) MOVING GPS points and \(totalDistance)m from activity")
            
            // Return the filtered coordinates and the correct distance
            return (coordinates: filteredCoordinates, totalDistanceMeters: totalDistance)
        }
    
/*    func extractRouteFromActivity(activityId: Int) async throws -> [CLLocationCoordinate2D] {
        await refreshTokenIfNeededAsync()
        
        guard let accessToken = currentTokens?.accessToken else {
            throw StravaError.notAuthenticated
        }
        
        // Fetch streams with latlng data
        let streams = try await fetchActivityStreams(activityId: activityId)
        
        guard let latlngData = streams.latlng?.data, !latlngData.isEmpty else {
            throw StravaError.noRouteData
        }
        
        // Convert to CLLocationCoordinate2D array
        let coordinates = latlngData.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count == 2 else { return nil }
            let lat = pair[0]
            let lon = pair[1]
            
            // Validate coordinates
            guard abs(lat) <= 90, abs(lon) <= 180, lat != 0, lon != 0 else {
                return nil
            }
            
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        
        guard !coordinates.isEmpty else {
            throw StravaError.noRouteData
        }
        
        print("StravaService: Extracted \(coordinates.count) GPS points from activity")
        return coordinates
    }
*/
    /// Decodes Google's encoded polyline format to coordinates
    private func decodePolyline(_ polyline: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        var index = polyline.startIndex
        var lat = 0
        var lng = 0
        
        while index < polyline.endIndex {
            var result = 1
            var shift = 0
            var b: Int
            
            repeat {
                b = Int(polyline[index].asciiValue! - 63) - 1
                index = polyline.index(after: index)
                result += b << shift
                shift += 5
            } while b >= 0x1f
            
            lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            
            result = 1
            shift = 0
            
            repeat {
                b = Int(polyline[index].asciiValue! - 63) - 1
                index = polyline.index(after: index)
                result += b << shift
                shift += 5
            } while b >= 0x1f
            
            lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            
            let coordinate = CLLocationCoordinate2D(
                latitude: Double(lat) / 1e5,
                longitude: Double(lng) / 1e5
            )
            coordinates.append(coordinate)
        }
        
        return coordinates
    }

    // MARK: - Debug Helper
    func getStoredAthleteId() -> Int? {
        let athleteId = UserDefaults.standard.integer(forKey: "strava_athlete_id")
        print("StravaService: Stored athlete ID: \(athleteId)")
        return athleteId > 0 ? athleteId : nil
    }
    
    // MARK: - Error Types
    enum StravaError: LocalizedError {
        case notAuthenticated
        case invalidURL
        case invalidResponse
        case apiError(statusCode: Int)
        case streamsNotAvailable
        case noRouteData
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Not authenticated with Strava"
            case .invalidURL:
                return "Invalid API URL"
            case .invalidResponse:
                return "Invalid response from Strava"
            case .apiError(let code):
                return "Strava API error: \(code)"
            case .streamsNotAvailable:
                return "Detailed activity data not available for this ride"
            case .noRouteData:  // ✅ ADD THIS
                return "No GPS route data available"
            }
        }
    }
}

// MARK: - Strava Routes Models

struct StravaRoute: Codable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let distance: Double // meters
    let elevation_gain: Double // meters
    let type: Int // 1 = ride, 2 = run
    let sub_type: Int // 1 = road, 2 = mtb, etc.
    let isPrivate: Bool
    let starred: Bool
    let timestamp: Int
    
    enum CodingKeys: String, CodingKey {
         case id, name, description, distance, elevation_gain, type, sub_type, starred, timestamp
         case isPrivate = "private"
     }
      
    var distanceKm: Double {
        distance / 1000.0
    }
    
    var distanceMiles: Double {
        distance / 1609.34
    }
    
    var routeType: String {
        switch sub_type {
        case 1: return "Road"
        case 2: return "MTB"
        case 3: return "Cross"
        case 4: return "Trail"
        case 5: return "Mixed"
        default: return "Ride"
        }
    }
    
    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}

struct StravaRouteDetail: Codable {
    let id: Int
    let name: String
    let description: String?
    let distance: Double
    let elevation_gain: Double
    let map: RouteMap?
    
    struct RouteMap: Codable {
        let id: String
        let polyline: String?
        let summary_polyline: String?
    }
}

extension StravaService {
    
    /// Fetches ALL activities (not just rides) for training load calculation
    /// This is a simple wrapper that uses the existing fetchRecentActivities method
    func fetchAllActivitiesForTrainingLoad(
        startDate: Date,
        endDate: Date = Date()
    ) async throws -> [StravaActivitySummary] {
        
        // Calculate how many days of activities to fetch
        let daysSinceStart = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 90
        
        // Fetch in batches to get all activities
        var allActivities: [StravaActivity] = []
        var currentPage = 1
        let perPage = 200 // Strava max
        
        // Keep fetching until we get activities older than startDate
        while true {
            let pageActivities = try await fetchRecentActivities(page: currentPage, perPage: perPage)
            
            if pageActivities.isEmpty {
                break // No more activities
            }
            
            // Filter activities within date range
            let filteredActivities = pageActivities.filter { activity in
                guard let activityDate = activity.startDate else { return false }
                return activityDate >= startDate && activityDate <= endDate
            }
            
            allActivities.append(contentsOf: filteredActivities)
            
            // Check if we've gone past the start date
            if let oldestActivityDate = pageActivities.last?.startDate,
               oldestActivityDate < startDate {
                break // We've fetched everything in range
            }
            
            // If we got fewer than perPage, we've reached the end
            if pageActivities.count < perPage {
                break
            }
            
            currentPage += 1
            
            // Safety check to prevent infinite loops
            if currentPage > 50 { // Max 10,000 activities
                print("⚠️ Training Load Sync: Reached maximum page limit")
                break
            }
        }
        
        // Convert to summary format
        let summaries = allActivities.map { activity in
            StravaActivitySummary(
                id: activity.id,
                name: activity.name,
                type: activity.type,
                startDate: activity.startDate ?? Date(),
                movingTime: activity.moving_time,
                elapsedTime: activity.elapsed_time,
                distance: activity.distance,
                averageWatts: activity.average_watts,
                weightedAverageWatts: activity.average_watts,
                sufferScore: activity.suffer_score,
                averageHeartrate: activity.average_heartrate,
                maxHeartrate: activity.max_heartrate,
                kilojoules: activity.kilojoules
            )
        }
        
        print("📊 Strava Sync: Fetched \(summaries.count) activities from \(startDate.formatted(date: .abbreviated, time: .omitted))")
        
        return summaries
    }
}
