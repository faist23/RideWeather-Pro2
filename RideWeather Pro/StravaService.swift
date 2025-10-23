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
    let firstname: String?
    let lastname: String?
}

// MARK: - Main Service
@MainActor
class StravaService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    // MARK: - Configuration
    private var stravaConfig: [String: String]?
    private var clientId: String { configValue(forKey: "StravaClientID") ?? "INVALID_CLIENT_ID" }
    private var clientSecret: String { configValue(forKey: "StravaClientSecret") ?? "INVALID_CLIENT_SECRET" }

    private let redirectUri = "https://faist23.github.io/rideweatherpro-redirect/strava-redirect.html"
    private let scope = "activity:read_all,profile:read_all"

    // MARK: - Published State
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String? = nil
    @Published var athleteName: String? = nil

    // MARK: - Internal State
    private var webAuthSession: ASWebAuthenticationSession?
    private var currentTokens: StravaTokens? {
        didSet {
            isAuthenticated = currentTokens != nil
            saveTokensToKeychain()
        }
    }

    // Separate Keychain slot for athlete name (so we persist connection state even if tokens expire)
    private let athleteNameKey = "strava_athlete_name"

    override init() {
        super.init()
        loadConfig()
        loadTokensFromKeychain()
        loadAthleteNameFromKeychain() // ✅ restore athlete name
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

                    // ✅ Store athlete name and update UI
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
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? UIWindow()
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

}

/*
 //
//  StravaService.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 10/21/25.
//

import Foundation
import AuthenticationServices // Correct framework for ASWebAuthenticationSession
import Combine
import UIKit // Needed for UIWindow via ASPresentationAnchor

// Basic structure for storing token data (Using Keychain)
struct StravaTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval // Store expiry timestamp (seconds since 1970)
}

// Struct to decode the JSON response from Strava's token endpoint
struct StravaTokenResponse: Decodable {
    let token_type: String
    let expires_at: TimeInterval
    let expires_in: Int
    let refresh_token: String
    let access_token: String
    // Add athlete info if it's included in the response and needed
    // let athlete: StravaAthlete?
}

@MainActor // Ensure UI updates happen on the main thread
class StravaService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    // MARK: - Configuration (Secrets Management)
    private var stravaConfig: [String: String]?

    private var clientId: String {
        // Safely access config, provide a non-functional default if missing
        return configValue(forKey: "StravaClientID") ?? "INVALID_CLIENT_ID"
    }

    private var clientSecret: String {
        // Safely access config, provide a non-functional default if missing
        // 🚨 This retrieves the secret securely from the loaded config
        return configValue(forKey: "StravaClientSecret") ?? "INVALID_CLIENT_SECRET"
    }

    private let redirectUri = "https://faist23.github.io/rideweatherpro-redirect/strava-redirect.html"
    private let scope = "activity:read_all" // Scope needed to read activities

    // MARK: - Published Properties for UI updates
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String? = nil
    @Published var athleteName: String? = nil

    // MARK: - Internal State
    private var webAuthSession: ASWebAuthenticationSession?
    private var currentTokens: StravaTokens? {
        didSet {
            isAuthenticated = currentTokens != nil
            // Save securely whenever tokens change (including becoming nil)
            saveTokensToKeychain()
        }
    }

    override init() {
        super.init()
        loadConfig() // Load secrets first
        loadTokensFromKeychain() // Load existing tokens on startup
    }

    // MARK: - Secrets Management (Loading Config)

    /// Loads configuration values from StravaConfig.plist
    private func loadConfig() {
        guard let path = Bundle.main.path(forResource: "StravaConfig", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            print("🚨 StravaService FATAL ERROR: StravaConfig.plist not found or incorrectly formatted!")
            // Disable Strava features or show a critical error UI in a real app
            errorMessage = "Critical configuration error. Strava integration disabled."
            stravaConfig = nil // Ensure config is nil if loading fails
            return
        }

        stravaConfig = dict
        print("StravaService: Configuration loaded successfully.")

        // Validate essential keys
        if configValue(forKey: "StravaClientID") == nil || configValue(forKey: "StravaClientSecret") == nil {
            print("🚨 StravaService WARNING: StravaClientID or StravaClientSecret missing in StravaConfig.plist!")
            errorMessage = "App configuration error. Strava integration may not function."
            // Consider setting isAuthenticated to false here as well
        }
    }

    /// Helper to safely access config values
    private func configValue(forKey key: String) -> String? {
        return stravaConfig?[key]
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding
    /// Provides the window for the authentication session to attach to.
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Iterate through connected scenes to find the active one
        let windowScene = UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive } // Ensure scene is active
            .first { $0 is UIWindowScene } // Find the first one that is a UIWindowScene
            as? UIWindowScene // Cast it

        // Get the key window from that scene
        let window = windowScene?.windows.first { $0.isKeyWindow }

        // Use the found window if available, otherwise fallback gracefully
        guard let keyWindow = window else {
            // Fallback 1: Try any window in the active scene
            if let fallbackWindow = windowScene?.windows.first {
                print("StravaService WARNING: Could not find key window, using first window in active scene as anchor.")
                return fallbackWindow
            }
            // Fallback 2: (Less Ideal) If no scene/window found, create temporary anchor.
            // This might happen if called very early in launch or in unusual app states.
            print("🚨 StravaService ERROR: Could not find any suitable window for presentation anchor! Using deprecated fallback.")
            // The deprecated init() might be needed as a last resort if ASPresentationAnchor(windowScene:) fails without a scene
            #if compiler(>=5.7) // Check Swift version if needed for deprecated API
                if #available(iOS 15, *) { // Check iOS version if needed
                     // Try creating based on generic scene info if possible, less reliable
                     if let scene = UIApplication.shared.connectedScenes.first {
                         return ASPresentationAnchor(windowScene: scene as! UIWindowScene) // Force cast might be risky
                     }
                }
            #endif
            // Absolute last resort
            return ASPresentationAnchor()
        }

        print("StravaService: Providing presentation anchor window: \(keyWindow)")
        return keyWindow
    }
    
    // MARK: - Authentication Flow

    /// Starts the Strava OAuth 2.0 authentication process.
    func authenticate() {
        // Prevent authentication if config is invalid
        guard stravaConfig != nil,
              clientId != "INVALID_CLIENT_ID",
              clientSecret != "INVALID_CLIENT_SECRET" else {
            errorMessage = "Strava integration is not configured correctly. Check StravaConfig.plist."
            print("StravaService Error: Attempted authentication without valid config.")
            return
        }

        errorMessage = nil
        print("StravaService: Starting authentication...")

        var components = URLComponents(string: "https://www.strava.com/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "force"), // Use "force" to always show consent screen
            URLQueryItem(name: "scope", value: scope)
        ]

        guard let authURL = components.url else {
            errorMessage = "Could not create Strava authorization URL."
            print("StravaService Error: \(errorMessage!)")
            return
        }

        print("StravaService: Auth URL: \(authURL.absoluteString)")

        // Initialize the session
        self.webAuthSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "rideweatherpro" // Your app's custom URL scheme
        ) { [weak self] (callbackURL, error) in
 
            // --- ADD DEBUGGING HERE ---
                    print("StravaService: ASWebAuthenticationSession completion handler called.")
                    if let url = callbackURL {
                        print("StravaService: Completion handler received URL: \(url.absoluteString)")
                    }
                    if let err = error {
                        print("StravaService: Completion handler received error: \(err.localizedDescription)")
                        // Specifically check for cancellation code
                        if (err as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                             print("StravaService: Error was cancellation.")
                        }
                    }
                    // --- END DEBUGGING ---
            
            guard let self = self else { return }

            print("StravaService: Callback received!") // ADD THIS
            
            // Handle potential errors (user cancellation, network issues)
            if let error = error {
                let asError = error as NSError
                print("StravaService: Error domain: \(asError.domain), code: \(asError.code)") // ADD THIS
                
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    print("StravaService: Authentication cancelled by user.")
                } else {
                    self.errorMessage = "Authentication failed: \(error.localizedDescription)"
                    print("StravaService Error: \(self.errorMessage!)")
                }
                return
            }
            
            guard let successURL = callbackURL else {
                self.errorMessage = "Authentication callback URL was missing."
                print("StravaService Error: \(self.errorMessage!)")
                return
            }
            
            print("StravaService: Received callback URL: \(successURL.absoluteString)")
            self.handleRedirect(url: successURL)
        }
        
        self.webAuthSession?.presentationContextProvider = self
        self.webAuthSession?.prefersEphemeralWebBrowserSession = true
 
        // --- ADD THIS LOG ---
        print("StravaService: Final URL before start: \(authURL.absoluteString)")
        // --- END ADD LOG ---
        
        print("StravaService: About to start web auth session") // ADD THIS
        let started = self.webAuthSession?.start() // CAPTURE THE RESULT
        print("StravaService: Web auth session started: \(started ?? false)") // ADD THIS
    }

    /// Handles the redirect URL from Strava (Internal access level).
    func handleRedirect(url: URL) {
        print("StravaService: Handling redirect...")
        // Verify the URL scheme and host match what we expect
        guard url.scheme == "rideweatherpro", url.host == "strava-auth" else {
            print("StravaService: Redirect URL \(url.absoluteString) does not match expected scheme/host.")
            return
        }

        // Parse the URL components to find query parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            errorMessage = "Could not parse callback URL components."
            print("StravaService Error: \(errorMessage!)")
            return
        }

        // Look for the 'code' parameter (success)
        if let codeItem = queryItems.first(where: { $0.name == "code" }), let code = codeItem.value {
            print("StravaService: Authorization code received.")
            // Exchange the temporary code for permanent tokens
            exchangeToken(code: code)
        // Look for the 'error' parameter (failure)
        } else if let errorItem = queryItems.first(where: { $0.name == "error" }), let errorDesc = errorItem.value {
            errorMessage = "Strava authorization error: \(errorDesc.replacingOccurrences(of: "_", with: " "))" // Make error readable
            print("StravaService Error: \(errorMessage!)")
        } else {
            errorMessage = "Callback URL did not contain 'code' or 'error'."
            print("StravaService Error: \(errorMessage!)")
        }
    }

    /// Exchanges the authorization code for access and refresh tokens.
    private func exchangeToken(code: String) {
        print("StravaService: Exchanging code for tokens...")
        print("StravaService: Code received: \(code)") // ADD THIS
        // Double-check config before proceeding
        guard stravaConfig != nil,
              clientId != "INVALID_CLIENT_ID",
              clientSecret != "INVALID_CLIENT_SECRET" else {
             errorMessage = "Strava integration is not configured correctly."
             print("StravaService Error: Attempted token exchange without valid config.")
             return
         }

        print("StravaService: Using Client ID: \(clientId)") // ADD THIS
        print("StravaService: Client Secret length: \(clientSecret.count) chars") // ADD THIS - don't print the actual secret

        guard let tokenURL = URL(string: "https://www.strava.com/oauth/token") else {
            print("StravaService Error: Invalid token URL.")
            return
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        // Strava expects form URL encoded data for token exchange
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Build the request body
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret), // Use loaded secret
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "grant_type", value: "authorization_code") // Specify code exchange
        ]

        // Add the body to the request
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        // ADD THIS to see what's being sent
        if let bodyString = String(data: request.httpBody!, encoding: .utf8) {
            // Redact the secret for safety
            let redactedBody = bodyString.replacingOccurrences(of: clientSecret, with: "***REDACTED***")
            print("StravaService: Request body: \(redactedBody)")
        }

        // Perform the network request
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            // Ensure UI updates happen on the main thread
            Task { @MainActor in
                if let error = error {
                    self.errorMessage = "Token exchange network failed: \(error.localizedDescription)"
                    print("StravaService Error: \(self.errorMessage!)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                     self.errorMessage = "Invalid response received from token endpoint."
                     print("StravaService Error: \(self.errorMessage!)")
                     return
                 }

                guard let data = data else {
                    self.errorMessage = "No data received from token endpoint."
                    print("StravaService Error: \(self.errorMessage!)")
                    return
                }

                // Log the raw response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("StravaService: Token Response (\(httpResponse.statusCode)): \(responseString)")
                }

                // Check for successful HTTP status code
                guard httpResponse.statusCode == 200 else {
                    self.errorMessage = "Token exchange failed: Status \(httpResponse.statusCode)"
                     // Try to parse specific error message from Strava's JSON response
                     if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let message = errorJson["message"] as? String {
                         self.errorMessage?.append(" - \(message)")
                     }
                    print("StravaService Error: \(self.errorMessage!)")
                    return
                }

                // Decode the successful JSON response
                do {
                    let decoder = JSONDecoder()
                    // Handle potential snake_case vs camelCase mismatch if needed
                    // decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let tokenResponse = try decoder.decode(StravaTokenResponse.self, from: data)

                    print("StravaService: Tokens received successfully.")
                    // Create and store the tokens securely
                    self.currentTokens = StravaTokens(
                        accessToken: tokenResponse.access_token,
                        refreshToken: tokenResponse.refresh_token,
                        expiresAt: tokenResponse.expires_at // Use the absolute expiry time
                    )
                    print("StravaService: Authentication complete.")
                    self.errorMessage = nil // Clear any previous errors on success

                } catch {
                    self.errorMessage = "Failed to decode token response: \(error.localizedDescription)"
                    print("StravaService Error: \(self.errorMessage!)")
                }
            }
        }
        task.resume() // Start the network request
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

    func disconnect() {
        // Clear any saved tokens
        // (use Keychain/Defaults as appropriate)
        self.isAuthenticated = false
        self.athleteName = nil
        print("StravaService: User disconnected.")
    }

    // MARK: - API Calls (Placeholder for fetching activities)
    /// Fetches activities, ensuring the access token is valid first.
    func fetchActivities( /* Add parameters like startDate, endDate, page, etc. */ completion: @escaping (Result<Void, Error>) -> Void) {
        // Step 1: Ensure token is valid or refresh it
        refreshTokenIfNeeded { [weak self] result in
             guard let self = self else { return }

             switch result {
             case .success:
                 // Step 2: Ensure we have an access token after potential refresh
                 guard let accessToken = self.currentTokens?.accessToken else {
                     let error = NSError(domain: "StravaService", code: -5, userInfo: [NSLocalizedDescriptionKey: "Missing access token after refresh check"])
                      Task { @MainActor in self.errorMessage = "Authentication error. Please reconnect Strava." }
                     completion(.failure(error))
                     return
                 }

                 // Step 3: Make the actual API call to fetch activities
                 print("StravaService: Making API call to fetch activities...")
                 // TODO: Construct URL (e.g., https://www.strava.com/api/v3/athlete/activities)
                 // TODO: Add parameters (before, after, page, per_page)
                 // TODO: Create URLRequest, add Authorization header: "Bearer \(accessToken)"
                 // TODO: Use URLSession to perform the GET request
                 // TODO: Decode the [StravaActivity] response
                 // TODO: Handle pagination if necessary
                 // TODO: Call completion(.success(decodedActivities)) or completion(.failure(error))

                 // Placeholder implementation:
                 print("   (Actual API call implementation pending)")
                 completion(.success(())) // Replace with actual result

             case .failure(let error):
                 // Refresh failed, cannot proceed
                 print("StravaService: Cannot fetch activities, token refresh failed.")
                  Task { @MainActor in self.errorMessage = "Could not connect to Strava. Please try reconnecting." }
                 completion(.failure(error))
             }
         }
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

     /// Disconnects from Strava by clearing local tokens.
     func disconnect() {
         // TODO: Add call to Strava's deauthorize endpoint (best practice)
         // Make a POST request to https://www.strava.com/oauth/deauthorize
         // Include the current access token: 'Authorization: Bearer YOUR_ACCESS_TOKEN'
         // Handle response/errors appropriately.

         // Clear local tokens (this triggers saveTokensToKeychain, which deletes them)
         currentTokens = nil
         print("StravaService: Disconnected and cleared local tokens.")
         // Optionally clear related user data (athlete name, etc.)
     }
}
*/
