//
//  StravaTokens.swift
//  RideWeather Pro
//
//  Created by Craig Faist on 10/21/25.
//


import Foundation
import AuthenticationServices // Import the framework for ASWebAuthenticationSession
import Combine // Needed for ObservableObject

// Basic structure for storing token data (replace with Keychain later)
struct StravaTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval // Store expiry timestamp
}

@MainActor // Ensure UI updates happen on the main thread
class StravaService: ObservableObject {

    // MARK: - Configuration (Move Secret out of code!)
    private let clientId = "81681"
    // 🚨 WARNING: Do NOT commit this secret to Git! Use environment variables or a config file.
    private let clientSecret = "ec063dddd9556fc6cbc912f4599fd753d8bdeaa2"
    private let redirectUri = "rideweatherpro://strava-auth" // Must match URL scheme + host
    private let scope = "activity:read_all" // Scope needed to read activities

    // MARK: - Published Properties for UI updates
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: - Internal State
    private var webAuthSession: ASWebAuthenticationSession?
    private var currentTokens: StravaTokens? {
        didSet {
            // Update authentication status
            isAuthenticated = currentTokens != nil
            // TODO: Persist tokens securely (Keychain)
            saveTokensToUserDefaults() // Placeholder
        }
    }

    init() {
        // Load existing tokens when the service is created
        loadTokensFromUserDefaults() // Placeholder
    }

    // MARK: - Authentication Flow

    /// Starts the Strava OAuth 2.0 authentication process.
    func authenticate() {
        errorMessage = nil // Clear previous errors
        print("StravaService: Starting authentication...")

        var components = URLComponents(string: "https://www.strava.com/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"), // Or "force"
            URLQueryItem(name: "scope", value: scope)
        ]

        guard let authURL = components.url else {
            errorMessage = "Could not create Strava authorization URL."
            print("StravaService Error: \(errorMessage!)")
            return
        }

        print("StravaService: Auth URL: \(authURL.absoluteString)")

        // Use ASWebAuthenticationSession for the login flow
        self.webAuthSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "rideweatherpro" // Your app's custom scheme
        ) { [weak self] (callbackURL, error) in
            guard let self = self else { return }

            // Check for errors (like user cancelling)
            if let error = error {
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    print("StravaService: Authentication cancelled by user.")
                    // Don't necessarily show an error message for cancellation
                } else {
                    self.errorMessage = "Authentication failed: \(error.localizedDescription)"
                    print("StravaService Error: \(self.errorMessage!)")
                }
                return
            }

            // Successfully received callback URL
            guard let successURL = callbackURL else {
                self.errorMessage = "Authentication callback URL was missing."
                print("StravaService Error: \(self.errorMessage!)")
                return
            }

            print("StravaService: Received callback URL: \(successURL.absoluteString)")
            // Handle the redirect to extract the code
            self.handleRedirect(url: successURL)
        }

        // Required for ASWebAuthenticationSession
        // You might need to hold a reference to the window scene in your App struct
        // and pass it down or access it globally if needed. For now, try finding it.
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
             errorMessage = "Could not get window scene for authentication."
             print("StravaService Error: \(errorMessage!)")
             return
         }
        self.webAuthSession?.presentationContextProvider = windowScene.windows.first?.rootViewController as? ASPresentationAnchorProvider

        // Start the session
        self.webAuthSession?.start()
    }

    /// Handles the redirect URL from Strava after user authorization.
    private func handleRedirect(url: URL) {
        print("StravaService: Handling redirect...")
        // Check if the URL contains the expected redirect URI host/path
        guard url.scheme == "rideweatherpro", url.host == "strava-auth" else {
            print("StravaService: Redirect URL does not match expected scheme/host.")
            return // Or handle error appropriately
        }

        // Parse the URL query parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            errorMessage = "Could not parse callback URL components."
            print("StravaService Error: \(errorMessage!)")
            return
        }

        // Find the authorization code
        if let codeItem = queryItems.first(where: { $0.name == "code" }), let code = codeItem.value {
            print("StravaService: Authorization code received.")
            // Exchange the code for tokens
            exchangeToken(code: code)
        } else if let errorItem = queryItems.first(where: { $0.name == "error" }), let errorDesc = errorItem.value {
            errorMessage = "Strava authorization error: \(errorDesc)"
            print("StravaService Error: \(errorMessage!)")
        } else {
            errorMessage = "Callback URL did not contain code or error."
            print("StravaService Error: \(errorMessage!)")
        }
    }

    /// Exchanges the authorization code for access and refresh tokens.
    private func exchangeToken(code: String) {
        print("StravaService: Exchanging code for tokens...")
        guard let tokenURL = URL(string: "https://www.strava.com/oauth/token") else { return }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "grant_type", value: "authorization_code")
        ]

        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            // Use Task to hop back to the MainActor for UI updates
            Task { @MainActor in
                if let error = error {
                    self.errorMessage = "Token exchange failed: \(error.localizedDescription)"
                    print("StravaService Error: \(self.errorMessage!)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                     self.errorMessage = "Invalid response from token endpoint."
                     print("StravaService Error: \(self.errorMessage!)")
                     return
                 }

                guard let data = data else {
                    self.errorMessage = "No data received from token endpoint."
                    print("StravaService Error: \(self.errorMessage!)")
                    return
                }

                // Print raw response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("StravaService: Token Response (\(httpResponse.statusCode)): \(responseString)")
                }

                guard httpResponse.statusCode == 200 else {
                    self.errorMessage = "Token exchange error: Status \(httpResponse.statusCode)"
                     // Try to decode error message from Strava if available
                     if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let message = errorJson["message"] as? String {
                         self.errorMessage?.append(" - \(message)")
                     }
                    print("StravaService Error: \(self.errorMessage!)")
                    return
                }

                // Decode the successful JSON response
                do {
                    let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)
                    print("StravaService: Tokens received successfully.")
                    // Store tokens securely
                    self.currentTokens = StravaTokens(
                        accessToken: tokenResponse.access_token,
                        refreshToken: tokenResponse.refresh_token,
                        expiresAt: tokenResponse.expires_at
                    )
                    // TODO: Securely save tokens to Keychain
                    print("StravaService: Authentication complete.")
                    self.errorMessage = nil // Clear error on success

                } catch {
                    self.errorMessage = "Failed to decode token response: \(error.localizedDescription)"
                    print("StravaService Error: \(self.errorMessage!)")
                }
            }
        }
        task.resume()
    }

    // MARK: - Token Refresh (Implement Later)
    func refreshTokenIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        // TODO: Check if currentTokens exist and if expiresAt is in the past
        // If needed, make a POST request to /oauth/token with:
        // grant_type=refresh_token
        // refresh_token=YOUR_REFRESH_TOKEN
        // client_id, client_secret
        // Update currentTokens with the new access_token, refresh_token, expires_at
        // Call completion handler
        print("StravaService: Token refresh needed (implementation pending).")
        completion(.success(())) // Placeholder
    }

    // MARK: - API Calls (Implement Later)
    func fetchActivities( /* ... parameters ... */ ) {
        // TODO: Implement API call using access_token
        print("StravaService: Fetching activities (implementation pending).")
    }

    // MARK: - Token Persistence (Placeholder - Use Keychain!)
    // These are placeholders using UserDefaults for simplicity during initial setup.
    // **REPLACE WITH KEYCHAIN LATER FOR SECURITY.**
    private let tokenKey = "stravaTokens"

    private func saveTokensToUserDefaults() {
        guard let tokens = currentTokens else {
            UserDefaults.standard.removeObject(forKey: tokenKey)
            return
        }
        if let encoded = try? JSONEncoder().encode(tokens) {
            UserDefaults.standard.set(encoded, forKey: tokenKey)
            print("StravaService: Tokens saved to UserDefaults (INSECURE - REPLACE WITH KEYCHAIN)")
        }
    }

    private func loadTokensFromUserDefaults() {
        if let savedData = UserDefaults.standard.data(forKey: tokenKey),
           let decodedTokens = try? JSONDecoder().decode(StravaTokens.self, from: savedData) {
            self.currentTokens = decodedTokens
            print("StravaService: Tokens loaded from UserDefaults (INSECURE - REPLACE WITH KEYCHAIN)")
            // Optionally: Trigger refresh check on load if needed
             Task { @MainActor in
                 // Example: Check if token is expired or close to expiring
                 if Date().timeIntervalSince1970 > (currentTokens?.expiresAt ?? 0) - 3600 { // Check if within 1 hour of expiry
                     print("StravaService: Token needs refresh upon loading.")
                     refreshTokenIfNeeded { _ in } // Trigger refresh
                 }
             }
        } else {
            print("StravaService: No saved tokens found.")
        }
    }

     func disconnect() {
         // TODO: Add call to Strava's deauthorize endpoint if needed
         // https://developers.strava.com/docs/authentication/#deauthorization

         // Clear local tokens
         currentTokens = nil
         print("StravaService: Disconnected and cleared tokens.")
     }
}

// MARK: - Helper Structs for Decoding

struct StravaTokenResponse: Decodable {
    let token_type: String
    let expires_at: TimeInterval
    let expires_in: Int
    let refresh_token: String
    let access_token: String
    // Add athlete info if it's included in the response
    // let athlete: StravaAthlete?
}

// Add ASPresentationAnchorProvider conformance to your RootViewController or relevant VC
// Example if using UIKit App Delegate structure:
 extension UIViewController: ASPresentationAnchorProvider {
     public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
         return self.view.window ?? ASPresentationAnchor()
     }
 }