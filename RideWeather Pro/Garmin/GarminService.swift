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

@MainActor
class GarminService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    // MARK: - Configuration
    private var garminConfig: [String: String]?
    private var clientId: String { configValue(forKey: "GarminClientID") ?? "INVALID_CLIENT_ID" }
    private var clientSecret: String { configValue(forKey: "GarminClientSecret") ?? "INVALID_CLIENT_SECRET" }
    
    // OAuth 2.0 PKCE Endpoints
    private let authUrl = "https://diauth.garmin.com/di-oauth2-service/oauth/authorize"
    private let tokenUrl = "https://diauth.garmin.com/di-oauth2-service/oauth/token"
    private let apiBaseUrl = "https://apis.garmin.com"
    
    private let redirectUri = "https://faist23.github.io/rideweatherpro-redirect/garmin-redirect.html"
    private let scope = "activity:read_all profile:read_all course:write" // Request course write scope
    
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

    // MARK: - Authentication
    
    func authenticate() {
        guard garminConfig != nil, clientId != "INVALID_CLIENT_ID" else {
            errorMessage = "Invalid Garmin configuration."
            return
        }
        
        let pkce = generatePKCE()
        self.currentPkceVerifier = pkce.verifier
        
        var components = URLComponents(string: authUrl)!
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
            return
        }
        guard let pkceVerifier = self.currentPkceVerifier else {
            errorMessage = "Authentication failed: PKCE verifier was lost."
            return
        }
        exchangeToken(code: code, pkceVerifier: pkceVerifier)
    }

    private func exchangeToken(code: String, pkceVerifier: String) {
        guard let tokenURL = URL(string: tokenUrl) else { return }
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
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let tokenResponse = try decoder.decode(GarminTokenResponse.self, from: data)
                    
                    self.currentTokens = GarminTokens(
                        accessToken: tokenResponse.accessToken,
                        refreshToken: tokenResponse.refreshToken,
                        expiresAt: Date().timeIntervalSince1970 + tokenResponse.expiresIn
                    )
                    self.errorMessage = nil
                    await self.fetchUserName()
                } catch {
                    print("GarminService: Token decoding error: \(error)")
                    if let errorBody = String(data: data, encoding: .utf8) {
                        print("GarminService: Error body: \(errorBody)")
                    }
                    self.errorMessage = "Token decoding failed."
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
        deleteAthleteNameFromKeychain()
        isAuthenticated = false
    }

    // MARK: - API Methods
    
    func fetchUserName() async {
        try? await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { return }
        
        // This endpoint is from the Wellness API, often granted with activity scopes
        guard let url = URL(string: "\(apiBaseUrl)/wellness-api/rest/user/permissions") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return
            }
            
            // We don't need to decode the response, just knowing it's valid is enough
            // to assume the token works. We can't get the user's name directly.
            let name = "Garmin User"
            self.athleteName = name
            saveAthleteNameToKeychain(name)
            
        } catch {
            print("GarminService: Could not fetch user permissions: \(error.localizedDescription)")
        }
    }
    
    /// Uploads a generated .FIT file as a new Course to the user's Garmin Connect account.
    func uploadCourse(fitData: Data, courseName: String) async throws {
        try await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { throw GarminError.notAuthenticated }
        
        // This is the placeholder URL. You will need to confirm this in your
        // Garmin Developer Portal API documentation for the "Courses API".
        guard let url = URL(string: "\(apiBaseUrl)/v1/courses") else {
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
        body.append("Content-Disposition: form-data; name=\"name\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(courseName)\r\n".data(using: .utf8)!)
        
        // FIT File Data
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
        
        // 201 Created is the typical success response for a POST
        guard (200...299).contains(httpResponse.statusCode) else {
            print("GarminService: Upload failed. Status: \(httpResponse.statusCode). Response: \(String(data: data, encoding: .utf8) ?? "N/A")")
            throw GarminError.apiError(statusCode: httpResponse.statusCode)
        }
        
        print("GarminService: Course uploaded successfully!")
    }
    
    // MARK: - Not Supported (Client-Side)
    
    func fetchRoutes() async throws -> [Any] {
        // Garmin's API does not support client-side fetching of a user's route list.
        // This requires a server-side webhook integration.
        print("GarminService: Fetching routes is not supported by the client-side API.")
        throw GarminError.notSupported
    }

    func fetchRecentActivities() async throws -> [Any] {
        // Garmin's API does not support client-side fetching of a user's activity list.
        // This requires a server-side webhook integration.
        print("GarminService: Fetching activities is not supported by the client-side API.")
        throw GarminError.notSupported
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
        case notSupported
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Not authenticated with Garmin."
            case .invalidURL: return "Invalid API URL."
            case .invalidResponse: return "Invalid response from Garmin."
            case .apiError(let code): return "Garmin API error: \(code)."
            case .notSupported: return "This feature is not supported by the Garmin client-side API."
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

/*// MARK: - PKCE Extensions
extension Data {
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    static func random(length: Int) -> Data {
        var data = Data(count: length)
        _ = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, length, $0.baseAddress!)
        }
        return data
    }
}*/
