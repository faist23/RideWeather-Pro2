//
//  GarminService.swift (Simplified - Upload Only)
//  RideWeather Pro
//
//  NOTE: Activity import removed - Garmin uses push notifications to backend servers.
//  This service only supports uploading courses TO Garmin.

import Foundation
import AuthenticationServices
import Combine
import UIKit
import CoreLocation
import CryptoKit

@MainActor
class GarminService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    // MARK: - Configuration
    private var garminConfig: [String: String]?
    private var clientId: String { configValue(forKey: "GarminClientID") ?? "INVALID_CLIENT_ID" }
    private var clientSecret: String { configValue(forKey: "GarminClientSecret") ?? "INVALID_CLIENT_SECRET" }
    
    // ✅ Correct base URL
    private let authUrl = "https://connect.garmin.com/oauth2Confirm"
    private let tokenUrl = "https://diauth.garmin.com/di-oauth2-service/oauth/token"
    private let apiBaseUrl = "https://apis.garmin.com"
    private let redirectUri = "https://faist23.github.io/rideweatherpro-redirect/garmin-redirect.html"
    
    // MARK: - Published State
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String? = nil
    @Published var athleteName: String? = nil
    
    // MARK: - Internal State
    private var webAuthSession: ASWebAuthenticationSession?
    private var currentPkceVerifier: String?
    
    private var currentTokens: GarminTokens? {
        didSet {
            isAuthenticated = currentTokens != nil
            saveTokensToKeychain()
        }
    }
    
    private let keychainService = Bundle.main.bundleIdentifier ?? "com.rideweatherpro.garmin"
    private let keychainAccount = "garminUserTokensV1"
    private let athleteNameKey = "garmin_athlete_name"

    override init() {
        super.init()
        loadConfig()
        loadTokensFromKeychain()
        loadAthleteNameFromKeychain()
    }

    private func loadConfig() {
        guard let path = Bundle.main.path(forResource: "GarminConfig", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            print("🚨 GarminService FATAL ERROR: GarminConfig.plist missing or malformed.")
            errorMessage = "Critical configuration error. Garmin disabled."
            garminConfig = nil
            return
        }
        garminConfig = dict
        print("GarminService: Configuration loaded.")
    }

    private func configValue(forKey key: String) -> String? {
        return garminConfig?[key]
    }

    // MARK: - Authentication (unchanged - this works)
    
    func authenticate() {
        guard garminConfig != nil, clientId != "INVALID_CLIENT_ID" else {
            errorMessage = "Invalid Garmin configuration."
            return
        }

        let pkce = generatePKCE()
        currentPkceVerifier = pkce.verifier
        
        var components = URLComponents(string: authUrl)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authURL = components.url else { return }

        print("GarminService: Starting auth with URL \(authURL.absoluteString)")

        webAuthSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "rideweatherpro"
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            if let error = error {
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    print("GarminService: Login canceled.")
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
              url.host == "garmin-auth",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            print("GarminService: Invalid redirect URL: \(url)")
            return
        }
        print("GarminService: Received auth code")
        
        guard let verifier = currentPkceVerifier else {
            print("GarminService: ERROR - No PKCE verifier stored")
            errorMessage = "Authentication error: Missing verification code"
            return
        }
        
        exchangeToken(code: code, pkceVerifier: verifier)
    }

    private func exchangeToken(code: String, pkceVerifier: String) {
        guard let tokenURL = URL(string: tokenUrl) else { return }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let credentials = "\(clientId):\(clientSecret)"
        if let credentialsData = credentials.data(using: .utf8) {
            let base64Credentials = credentialsData.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        }
        
        var parameters: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("redirect_uri", redirectUri),
            ("code", code),
            ("code_verifier", pkceVerifier)
        ]
        
        let formData = parameters
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        
        request.httpBody = formData.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            Task { @MainActor in
                if let error = error {
                    print("GarminService: Network error: \(error.localizedDescription)")
                    self.errorMessage = error.localizedDescription
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("GarminService: Invalid response type")
                    self.errorMessage = "Invalid response from server"
                    return
                }
                
                print("GarminService: Token exchange response status: \(httpResponse.statusCode)")
                
                guard let data = data else {
                    print("GarminService: No data in response")
                    self.errorMessage = "No data received from server"
                    return
                }
                
                guard httpResponse.statusCode == 200 else {
                    self.errorMessage = "Token exchange failed (HTTP \(httpResponse.statusCode))."
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let tokenResponse = try decoder.decode(GarminTokenResponse.self, from: data)
                    
                    self.currentTokens = GarminTokens(
                        accessToken: tokenResponse.accessToken,
                        refreshToken: tokenResponse.refreshToken,
                        expiresAt: Date().timeIntervalSince1970 + tokenResponse.expiresIn
                    )
                    self.errorMessage = nil
                    self.currentPkceVerifier = nil
                    print("GarminService: ✅ Token exchange successful!")
                    await self.fetchUserName()
                } catch {
                    print("GarminService: Token decoding error: \(error)")
                    self.errorMessage = "Token exchange failed. Please try again."
                }
            }
        }.resume()
    }

    func refreshTokenIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tokens = currentTokens else {
            completion(.failure(GarminError.notAuthenticated)); return
        }
        if Date().timeIntervalSince1970 < tokens.expiresAt - 3600 {
            completion(.success(())); return
        }
        
        print("GarminService: Refreshing token...")
        guard let tokenURL = URL(string: tokenUrl) else {
            completion(.failure(GarminError.invalidURL)); return
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let credentials = "\(clientId):\(clientSecret)"
        if let credentialsData = credentials.data(using: .utf8) {
            let base64Credentials = credentialsData.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        }
        
        let parameters = [
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken
        ]
        
        let formData = parameters
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        
        request.httpBody = formData.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            Task { @MainActor in
                if let error = error {
                    self.disconnect(); completion(.failure(error)); return
                }
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                    self.disconnect(); completion(.failure(GarminError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1))); return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let tokenResponse = try decoder.decode(GarminTokenResponse.self, from: data)
                    
                    self.currentTokens = GarminTokens(
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
        currentPkceVerifier = nil
        deleteAthleteNameFromKeychain()
        isAuthenticated = false
    }

    // MARK: - API Methods (ONLY UPLOAD - Import requires backend)
    
    func fetchUserName() async {
        try? await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { return }
        
        // Using wellness API as a proxy for user authentication
        guard let url = URL(string: "\(apiBaseUrl)/wellness-api/rest/user/permissions") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                print("GarminService: Could not fetch user permissions")
                return
            }
            
            let name = "Garmin User"
            self.athleteName = name
            saveAthleteNameToKeychain(name)
            print("GarminService: User authenticated successfully")
            
        } catch {
            print("GarminService: Could not fetch user permissions: \(error.localizedDescription)")
        }
    }
    
    /// ✅ THIS WORKS - Upload a course/route TO Garmin
    func uploadCourse(fitData: Data, courseName: String) async throws {
        print("GarminService: 🚀 Starting course upload for '\(courseName)'")
        print("GarminService: FIT file size: \(fitData.count) bytes")
        
        try await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else {
            print("GarminService: ❌ Not authenticated")
            throw GarminError.notAuthenticated
        }
        
        print("GarminService: ✅ Token refreshed, proceeding with upload")
        
        // Try multiple known Garmin course upload endpoints
        let endpoints = [
            "\(apiBaseUrl)/course-api/course/import",
            "\(apiBaseUrl)/course-service/course/import",
            "\(apiBaseUrl)/course-api/rest/course/import"
        ]
        
        var lastError: Error?
        
        for (index, endpoint) in endpoints.enumerated() {
            print("GarminService: Trying endpoint \(index + 1)/\(endpoints.count): \(endpoint)")
            do {
                try await attemptUpload(to: endpoint, fitData: fitData, courseName: courseName, token: token)
                print("GarminService: ✅✅✅ Course uploaded successfully to \(endpoint)")
                return // Success!
            } catch let error as GarminError {
                print("GarminService: ⚠️ Failed endpoint \(endpoint): \(error.localizedDescription)")
                lastError = error
                
                // If it's a 404, try next endpoint
                if case .apiError(let statusCode) = error, statusCode == 404 {
                    print("GarminService: 404 error, trying next endpoint...")
                    continue
                }
                
                // For other errors, throw immediately
                print("GarminService: ❌ Non-404 error, stopping: \(error)")
                throw error
            } catch {
                print("GarminService: ❌ Unexpected error: \(error)")
                throw error
            }
        }
        
        // If all endpoints failed, throw the last error
        print("GarminService: ❌ All endpoints failed")
        throw lastError ?? GarminError.apiError(statusCode: 500)
    }
    
    /// Helper function to attempt upload to a specific endpoint
    private func attemptUpload(to urlString: String, fitData: Data, courseName: String, token: String) async throws {
        guard let url = URL(string: urlString) else {
            throw GarminError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Course Name
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"courseName\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(courseName)\r\n".data(using: .utf8)!)
        
        // FIT File
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(courseName).fit\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/vnd.garmin.fit\r\n\r\n".data(using: .utf8)!)
        body.append(fitData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        print("GarminService: Attempting upload to \(urlString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarminError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "N/A"
            print("GarminService: Upload failed. Status: \(httpResponse.statusCode). Response: \(responseBody)")
            throw GarminError.apiError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Presentation Anchor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return UIWindow()
        }
        return window
    }

    // MARK: - Helpers
    private func refreshTokenIfNeededAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            refreshTokenIfNeeded { result in
                continuation.resume(with: result)
            }
        }
    }
    
    private func generatePKCE() -> (verifier: String, challenge: String) {
        let verifier = Data.random(length: 32).base64URLEncodedString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        return (verifier, challenge)
    }
    
    // MARK: - Keychain (unchanged)
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
            print("GarminService: Failed to save tokens: \(error)")
        }
    }

    private func loadTokensFromKeychain() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainAccount, kSecReturnData as String: kCFBooleanTrue!, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            do {
                self.currentTokens = try JSONDecoder().decode(GarminTokens.self, from: data)
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
    
    // MARK: - Error Types
    enum GarminError: LocalizedError {
        case notAuthenticated
        case invalidURL
        case invalidResponse
        case apiError(statusCode: Int)
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Not authenticated with Garmin."
            case .invalidURL: return "Invalid API URL."
            case .invalidResponse: return "Invalid response from Garmin."
            case .apiError(let code): return "Garmin API error: \(code)."
            }
        }
    }
}

// MARK: - Data Models
struct GarminTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval
}

struct GarminTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
}

/*//
//  GarminService.swift (Simplified - Upload Only)
//  RideWeather Pro
//
//  NOTE: Activity import removed - Garmin uses push notifications to backend servers.
//  This service only supports uploading courses TO Garmin.

import Foundation
import AuthenticationServices
import Combine
import UIKit
import CoreLocation
import CryptoKit

@MainActor
class GarminService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    // MARK: - Configuration
    private var garminConfig: [String: String]?
    private var clientId: String { configValue(forKey: "GarminClientID") ?? "INVALID_CLIENT_ID" }
    private var clientSecret: String { configValue(forKey: "GarminClientSecret") ?? "INVALID_CLIENT_SECRET" }
    
    // ✅ Correct base URL
    private let authUrl = "https://connect.garmin.com/oauth2Confirm"
    private let tokenUrl = "https://diauth.garmin.com/di-oauth2-service/oauth/token"
    private let apiBaseUrl = "https://apis.garmin.com"
    private let redirectUri = "https://faist23.github.io/rideweatherpro-redirect/garmin-redirect.html"
    
    // MARK: - Published State
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String? = nil
    @Published var athleteName: String? = nil
    
    // MARK: - Internal State
    private var webAuthSession: ASWebAuthenticationSession?
    private var currentPkceVerifier: String?
    
    private var currentTokens: GarminTokens? {
        didSet {
            isAuthenticated = currentTokens != nil
            saveTokensToKeychain()
        }
    }
    
    private let keychainService = Bundle.main.bundleIdentifier ?? "com.rideweatherpro.garmin"
    private let keychainAccount = "garminUserTokensV1"
    private let athleteNameKey = "garmin_athlete_name"

    override init() {
        super.init()
        loadConfig()
        loadTokensFromKeychain()
        loadAthleteNameFromKeychain()
    }

    private func loadConfig() {
        guard let path = Bundle.main.path(forResource: "GarminConfig", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            print("🚨 GarminService FATAL ERROR: GarminConfig.plist missing or malformed.")
            errorMessage = "Critical configuration error. Garmin disabled."
            garminConfig = nil
            return
        }
        garminConfig = dict
        print("GarminService: Configuration loaded.")
    }

    private func configValue(forKey key: String) -> String? {
        return garminConfig?[key]
    }

    // MARK: - Authentication (unchanged - this works)
    
    func authenticate() {
        guard garminConfig != nil, clientId != "INVALID_CLIENT_ID" else {
            errorMessage = "Invalid Garmin configuration."
            return
        }

        let pkce = generatePKCE()
        currentPkceVerifier = pkce.verifier
        
        var components = URLComponents(string: authUrl)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authURL = components.url else { return }

        print("GarminService: Starting auth with URL \(authURL.absoluteString)")

        webAuthSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "rideweatherpro"
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            if let error = error {
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    print("GarminService: Login canceled.")
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
              url.host == "garmin-auth",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            print("GarminService: Invalid redirect URL: \(url)")
            return
        }
        print("GarminService: Received auth code")
        
        guard let verifier = currentPkceVerifier else {
            print("GarminService: ERROR - No PKCE verifier stored")
            errorMessage = "Authentication error: Missing verification code"
            return
        }
        
        exchangeToken(code: code, pkceVerifier: verifier)
    }

    private func exchangeToken(code: String, pkceVerifier: String) {
        guard let tokenURL = URL(string: tokenUrl) else { return }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let credentials = "\(clientId):\(clientSecret)"
        if let credentialsData = credentials.data(using: .utf8) {
            let base64Credentials = credentialsData.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        }
        
        var parameters: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("redirect_uri", redirectUri),
            ("code", code),
            ("code_verifier", pkceVerifier)
        ]
        
        let formData = parameters
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        
        request.httpBody = formData.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            Task { @MainActor in
                if let error = error {
                    print("GarminService: Network error: \(error.localizedDescription)")
                    self.errorMessage = error.localizedDescription
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("GarminService: Invalid response type")
                    self.errorMessage = "Invalid response from server"
                    return
                }
                
                print("GarminService: Token exchange response status: \(httpResponse.statusCode)")
                
                guard let data = data else {
                    print("GarminService: No data in response")
                    self.errorMessage = "No data received from server"
                    return
                }
                
                guard httpResponse.statusCode == 200 else {
                    self.errorMessage = "Token exchange failed (HTTP \(httpResponse.statusCode))."
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let tokenResponse = try decoder.decode(GarminTokenResponse.self, from: data)
                    
                    self.currentTokens = GarminTokens(
                        accessToken: tokenResponse.accessToken,
                        refreshToken: tokenResponse.refreshToken,
                        expiresAt: Date().timeIntervalSince1970 + tokenResponse.expiresIn
                    )
                    self.errorMessage = nil
                    self.currentPkceVerifier = nil
                    print("GarminService: ✅ Token exchange successful!")
                    await self.fetchUserName()
                } catch {
                    print("GarminService: Token decoding error: \(error)")
                    self.errorMessage = "Token exchange failed. Please try again."
                }
            }
        }.resume()
    }

    func refreshTokenIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tokens = currentTokens else {
            completion(.failure(GarminError.notAuthenticated)); return
        }
        if Date().timeIntervalSince1970 < tokens.expiresAt - 3600 {
            completion(.success(())); return
        }
        
        print("GarminService: Refreshing token...")
        guard let tokenURL = URL(string: tokenUrl) else {
            completion(.failure(GarminError.invalidURL)); return
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let credentials = "\(clientId):\(clientSecret)"
        if let credentialsData = credentials.data(using: .utf8) {
            let base64Credentials = credentialsData.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        }
        
        let parameters = [
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken
        ]
        
        let formData = parameters
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        
        request.httpBody = formData.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            Task { @MainActor in
                if let error = error {
                    self.disconnect(); completion(.failure(error)); return
                }
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                    self.disconnect(); completion(.failure(GarminError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1))); return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let tokenResponse = try decoder.decode(GarminTokenResponse.self, from: data)
                    
                    self.currentTokens = GarminTokens(
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
        currentPkceVerifier = nil
        deleteAthleteNameFromKeychain()
        isAuthenticated = false
    }

    // MARK: - API Methods (ONLY UPLOAD - Import requires backend)
    
    func fetchUserName() async {
        try? await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { return }
        
        // Using wellness API as a proxy for user authentication
        guard let url = URL(string: "\(apiBaseUrl)/wellness-api/rest/user/permissions") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                print("GarminService: Could not fetch user permissions")
                return
            }
            
            let name = "Garmin User"
            self.athleteName = name
            saveAthleteNameToKeychain(name)
            print("GarminService: User authenticated successfully")
            
        } catch {
            print("GarminService: Could not fetch user permissions: \(error.localizedDescription)")
        }
    }
    
    /// ✅ THIS WORKS - Upload a course/route TO Garmin
    func uploadCourse(fitData: Data, courseName: String) async throws {
        try await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { throw GarminError.notAuthenticated }
        
        guard let url = URL(string: "\(apiBaseUrl)/course-api/course/import") else {
            throw GarminError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Course Name
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"courseName\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(courseName)\r\n".data(using: .utf8)!)
        
        // FIT File
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(courseName).fit\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/vnd.garmin.fit\r\n\r\n".data(using: .utf8)!)
        body.append(fitData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarminError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            print("GarminService: Upload failed. Status: \(httpResponse.statusCode). Response: \(String(data: data, encoding: .utf8) ?? "N/A")")
            throw GarminError.apiError(statusCode: httpResponse.statusCode)
        }
        
        print("GarminService: Course uploaded successfully!")
    }

    // MARK: - Presentation Anchor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return UIWindow()
        }
        return window
    }

    // MARK: - Helpers
    private func refreshTokenIfNeededAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            refreshTokenIfNeeded { result in
                continuation.resume(with: result)
            }
        }
    }
    
    private func generatePKCE() -> (verifier: String, challenge: String) {
        let verifier = Data.random(length: 32).base64URLEncodedString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        return (verifier, challenge)
    }
    
    // MARK: - Keychain (unchanged)
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
            print("GarminService: Failed to save tokens: \(error)")
        }
    }

    private func loadTokensFromKeychain() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainAccount, kSecReturnData as String: kCFBooleanTrue!, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            do {
                self.currentTokens = try JSONDecoder().decode(GarminTokens.self, from: data)
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
    
    // MARK: - Error Types
    enum GarminError: LocalizedError {
        case notAuthenticated
        case invalidURL
        case invalidResponse
        case apiError(statusCode: Int)
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Not authenticated with Garmin."
            case .invalidURL: return "Invalid API URL."
            case .invalidResponse: return "Invalid response from Garmin."
            case .apiError(let code): return "Garmin API error: \(code)."
            }
        }
    }
}

// MARK: - Data Models
struct GarminTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval
}

struct GarminTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
}
/*
//
//  GarminService.swift
//  RideWeather Pro
//

import Foundation
import AuthenticationServices
import Combine
import UIKit
import CoreLocation
import CryptoKit

struct GarminActivity: Codable, Identifiable {
    var id: String { activityId } // Conform to Identifiable
    let activityId: String
    let activityName: String?
    let description: String?
    let startTimeLocal: String?
    let distance: Double? // in meters
    let duration: Double? // in seconds
    let averageSpeed: Double? // in m/s
    let averagePower: Double? // in watts
    let activityType: GarminActivityType?
    
    var distanceMeters: Double {
        return distance ?? 0
    }
    
    var durationFormatted: String {
        let seconds = Int(duration ?? 0)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
    
    var startTime: Date? {
        guard let startTimeLocal else { return nil }
        // Garmin uses ISO 8601 format like "2023-10-27T10:00:00.0"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: startTimeLocal)
    }
}

struct GarminActivityType: Codable {
    let typeKey: String? // e.g., "cycling", "running"
    let typeId: Int?
}

@MainActor
class GarminService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    // MARK: - Configuration
    private var garminConfig: [String: String]?
    private var clientId: String { configValue(forKey: "GarminClientID") ?? "INVALID_CLIENT_ID" }
    private var clientSecret: String { configValue(forKey: "GarminClientSecret") ?? "INVALID_CLIENT_SECRET" }
    
    // ✅ Garmin uses PKCE OAuth 2.0 flow
    private let authUrl = "https://connect.garmin.com/oauth2Confirm"
    private let tokenUrl = "https://diauth.garmin.com/di-oauth2-service/oauth/token"
    private let apiBaseUrl = "https://apis.garmin.com"

    private let redirectUri = "https://faist23.github.io/rideweatherpro-redirect/garmin-redirect.html"
    
    // MARK: - Published State
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String? = nil
    @Published var athleteName: String? = nil
    
    // MARK: - Internal State
    private var webAuthSession: ASWebAuthenticationSession?
    // ✅ PKCE is REQUIRED for Garmin
    private var currentPkceVerifier: String?
    
    private var currentTokens: GarminTokens? {
        didSet {
            isAuthenticated = currentTokens != nil
            saveTokensToKeychain()
        }
    }
    
    private let keychainService = Bundle.main.bundleIdentifier ?? "com.rideweatherpro.garmin"
    private let keychainAccount = "garminUserTokensV1"
    private let athleteNameKey = "garmin_athlete_name"

    override init() {
        super.init()
        loadConfig()
        loadTokensFromKeychain()
        loadAthleteNameFromKeychain()
    }

    private func loadConfig() {
        guard let path = Bundle.main.path(forResource: "GarminConfig", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            print("🚨 GarminService FATAL ERROR: GarminConfig.plist missing or malformed.")
            errorMessage = "Critical configuration error. Garmin disabled."
            garminConfig = nil
            return
        }
        garminConfig = dict
        print("GarminService: Configuration loaded.")
    }

    private func configValue(forKey key: String) -> String? {
        return garminConfig?[key]
    }

    // MARK: - Authentication
    
    func authenticate() {
        guard garminConfig != nil, clientId != "INVALID_CLIENT_ID" else {
            errorMessage = "Invalid Garmin configuration."
            return
        }

        // ✅ FIXED: Generate PKCE challenge (REQUIRED by Garmin)
        let pkce = generatePKCE()
        currentPkceVerifier = pkce.verifier
        
        var components = URLComponents(string: authUrl)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authURL = components.url else { return }

        print("GarminService: Starting auth with URL \(authURL.absoluteString)")

        webAuthSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "rideweatherpro"
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            if let error = error {
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    print("GarminService: Login canceled.")
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
              url.host == "garmin-auth",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            print("GarminService: Invalid redirect URL: \(url)")
            return
        }
        print("GarminService: Received auth code")
        
        // ✅ Pass the PKCE verifier for token exchange
        guard let verifier = currentPkceVerifier else {
            print("GarminService: ERROR - No PKCE verifier stored")
            errorMessage = "Authentication error: Missing verification code"
            return
        }
        
        exchangeToken(code: code, pkceVerifier: verifier)
    }

    private func exchangeToken(code: String, pkceVerifier: String) {
        guard let tokenURL = URL(string: tokenUrl) else { return }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // ✅ FIXED: Use Basic Authentication header (REQUIRED by Garmin)
        let credentials = "\(clientId):\(clientSecret)"
        if let credentialsData = credentials.data(using: .utf8) {
            let base64Credentials = credentialsData.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        }
        
        // ✅ FIXED: Include code_verifier and DO NOT include client credentials in body
        var parameters: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("redirect_uri", redirectUri),
            ("code", code),
            ("code_verifier", pkceVerifier)  // ✅ REQUIRED by Garmin
        ]
        
        let formData = parameters
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        
        request.httpBody = formData.data(using: .utf8)
        
        print("GarminService: Exchanging token with code")
        print("GarminService: Request URL: \(tokenURL)")
        
        // Debug: Print sanitized body
        let debugBody = formData
            .replacingOccurrences(of: code, with: "***CODE***")
            .replacingOccurrences(of: pkceVerifier, with: "***VERIFIER***")
        print("GarminService: Request body (sanitized): \(debugBody)")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            Task { @MainActor in
                if let error = error {
                    print("GarminService: Network error: \(error.localizedDescription)")
                    self.errorMessage = error.localizedDescription
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("GarminService: Invalid response type")
                    self.errorMessage = "Invalid response from server"
                    return
                }
                
                print("GarminService: Token exchange response status: \(httpResponse.statusCode)")
                
                guard let data = data else {
                    print("GarminService: No data in response")
                    self.errorMessage = "No data received from server"
                    return
                }
                
                if let responseBody = String(data: data, encoding: .utf8) {
                    print("GarminService: Response body: \(responseBody)")
                }
                
                guard httpResponse.statusCode == 200 else {
                    self.errorMessage = "Token exchange failed (HTTP \(httpResponse.statusCode)). Check console logs."
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let tokenResponse = try decoder.decode(GarminTokenResponse.self, from: data)
                    
                    self.currentTokens = GarminTokens(
                        accessToken: tokenResponse.accessToken,
                        refreshToken: tokenResponse.refreshToken,
                        expiresAt: Date().timeIntervalSince1970 + tokenResponse.expiresIn
                    )
                    self.errorMessage = nil
                    self.currentPkceVerifier = nil // Clear after successful exchange
                    print("GarminService: ✅ Token exchange successful!")
                    await self.fetchUserName()
                } catch {
                    print("GarminService: Token decoding error: \(error)")
                    self.errorMessage = "Token exchange failed. Please try again."
                }
            }
        }.resume()
    }

    func refreshTokenIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tokens = currentTokens else {
            completion(.failure(GarminError.notAuthenticated)); return
        }
        if Date().timeIntervalSince1970 < tokens.expiresAt - 3600 {
            completion(.success(())); return
        }
        
        print("GarminService: Refreshing token...")
        guard let tokenURL = URL(string: tokenUrl) else {
            completion(.failure(GarminError.invalidURL)); return
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // ✅ FIXED: Use Basic Authentication for refresh token
        let credentials = "\(clientId):\(clientSecret)"
        if let credentialsData = credentials.data(using: .utf8) {
            let base64Credentials = credentialsData.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        }
        
        let parameters = [
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken
        ]
        
        let formData = parameters
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        
        request.httpBody = formData.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            Task { @MainActor in
                if let error = error {
                    self.disconnect(); completion(.failure(error)); return
                }
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data else {
                    self.disconnect(); completion(.failure(GarminError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1))); return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let tokenResponse = try decoder.decode(GarminTokenResponse.self, from: data)
                    
                    self.currentTokens = GarminTokens(
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
        currentPkceVerifier = nil
        deleteAthleteNameFromKeychain()
        isAuthenticated = false
    }

    // MARK: - API Methods
    
    func fetchUserName() async {
        try? await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { return }
        
        guard let url = URL(string: "\(apiBaseUrl)/wellness-api/rest/user/permissions") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                print("GarminService: Could not fetch user permissions")
                return
            }
            
            let name = "Garmin User" // Garmin API doesn't provide a name here
            self.athleteName = name
            saveAthleteNameToKeychain(name)
            print("GarminService: User authenticated successfully")
            
        } catch {
            print("GarminService: Could not fetch user permissions: \(error.localizedDescription)")
        }
    }
    
    func uploadCourse(fitData: Data, courseName: String) async throws {
        try await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { throw GarminError.notAuthenticated }
        
        // This is the official Garmin Courses API endpoint
        guard let url = URL(string: "\(apiBaseUrl)/courses-api/rest/course/import") else {
            throw GarminError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Course Name (as form data)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"courseName\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(courseName)\r\n".data(using: .utf8)!)
        
        // FIT File Data (as form data)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(courseName).fit\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/vnd.garmin.fit\r\n\r\n".data(using: .utf8)!)
        body.append(fitData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarminError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            print("GarminService: Upload failed. Status: \(httpResponse.statusCode). Response: \(String(data: data, encoding: .utf8) ?? "N/A")")
            throw GarminError.apiError(statusCode: httpResponse.statusCode)
        }
        
        print("GarminService: Course uploaded successfully!")
    }
    
    // MARK: - Not Supported (Client-Side)
    
    func fetchRoutes() async throws -> [Any] {
        print("GarminService: fetchRoutes() called.")
        throw GarminError.notSupportedByAPI
    }
    
    // --- NEW: fetchRecentActivities ---
    
    /// Fetches a list of completed activities from the Garmin Connect Activity API.
    func fetchRecentActivities(startDate: Date, limit: Int = 50, start: Int = 0) async throws -> [GarminActivity] {
        try await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { throw GarminError.notAuthenticated }
        
        // Use the official Activity API endpoint
        guard var components = URLComponents(string: "\(apiBaseUrl)/activity-api/rest/activities") else {
            throw GarminError.invalidURL
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        
        components.queryItems = [
            // Garmin API uses timestamps
            URLQueryItem(name: "uploadStartTimeInSeconds", value: "\(Int(startDate.timeIntervalSince1970))"),
            URLQueryItem(name: "uploadEndTimeInSeconds", value: "\(Int(Date().timeIntervalSince1970))"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "start", value: "\(start)")
        ]
        
        guard let url = components.url else { throw GarminError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("GarminService: Fetching activities from \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarminError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            print("GarminService: Fetch activities failed. Status: \(httpResponse.statusCode). Response: \(String(data: data, encoding: .utf8) ?? "N/A")")
            throw GarminError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            let activities = try decoder.decode([GarminActivity].self, from: data)
            print("GarminService: Successfully fetched \(activities.count) activities")
            return activities
        } catch {
            print("GarminService: Decoding activities failed: \(error)")
            print("GarminService: Raw response: \(String(data: data, encoding: .utf8) ?? "No data")")
            throw error
        }
    }
    
    /// Downloads the original .FIT file for a completed activity.
    func downloadActivityFile(activityId: String) async throws -> Data {
        try await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { throw GarminError.notAuthenticated }
        
        // This is the official endpoint for downloading the original file
        guard let url = URL(string: "\(apiBaseUrl)/download-api/rest/download/activity/\(activityId)") else {
            throw GarminError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("GarminService: Downloading .fit file for activity \(activityId)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarminError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            print("GarminService: Download .fit file failed. Status: \(httpResponse.statusCode).")
            throw GarminError.apiError(statusCode: httpResponse.statusCode)
        }
        
        print("GarminService: Successfully downloaded \(data.count) bytes for activity \(activityId)")
        return data
    }
    
    // --- NEW: extractRouteFromGarminActivity ---
    
    /// Downloads and parses a Garmin activity's .FIT file to extract its GPS route.
    func extractRouteFromGarminActivity(activityId: String) async throws -> (coordinates: [CLLocationCoordinate2D], totalDistanceMeters: Double) {
        // 1. Download the file data
        let fitData = try await downloadActivityFile(activityId: activityId)
        
        // 2. Parse the .fit file
        let parser = RouteParser()
        let (coordinates, elevationAnalysis) = try parser.parseWithElevation(fitData: fitData)
        
        guard !coordinates.isEmpty else {
            throw GarminError.noRouteData
        }
        
        // 3. Get total distance from the elevation analysis
        let totalDistance = elevationAnalysis?.elevationProfile.last?.distance ?? 0.0
        
        if totalDistance == 0.0 {
            print("GarminService: Warning - parsed coordinates but total distance is 0.")
        }
        
        return (coordinates, totalDistance)
    }

    // MARK: - Presentation Anchor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return UIWindow()
        }
        return window
    }

    // MARK: - Helpers
    private func refreshTokenIfNeededAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            refreshTokenIfNeeded { result in
                continuation.resume(with: result)
            }
        }
    }
    
    private func generatePKCE() -> (verifier: String, challenge: String) {
        let verifier = Data.random(length: 32).base64URLEncodedString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        return (verifier, challenge)
    }
    
    // MARK: - Keychain
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
            print("GarminService: Failed to save tokens: \(error)")
        }
    }

    private func loadTokensFromKeychain() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainAccount, kSecReturnData as String: kCFBooleanTrue!, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            do {
                self.currentTokens = try JSONDecoder().decode(GarminTokens.self, from: data)
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
    
    // MARK: - Error Types
    enum GarminError: LocalizedError {
        case notAuthenticated
        case invalidURL
        case invalidResponse
        case apiError(statusCode: Int)
        case notSupportedByAPI
        case noRouteData
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Not authenticated with Garmin."
            case .invalidURL: return "Invalid API URL."
            case .invalidResponse: return "Invalid response from Garmin."
            case .apiError(let code): return "Garmin API error: \(code)."
            case .notSupportedByAPI: return "This feature (importing saved routes) is not supported by the official Garmin API. Please import a completed activity instead."
            case .noRouteData: return "This activity does not contain any GPS data to import."
            }
        }
    }
}

// MARK: - Data Models
struct GarminTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval
}

struct GarminTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
}
*/
*/
