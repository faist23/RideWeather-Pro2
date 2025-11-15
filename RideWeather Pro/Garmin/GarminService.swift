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
                    self.disconnect(); completion(.failure(GarminError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1, message: "refresh_token"))); return
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
        print("GarminService: fetchUserName() called")
        try? await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else {
            print("GarminService: No access token available")
            return
        }
        
        // Garmin's official OAuth API doesn't expose user profile names
        // We'll try the wellness API user ID endpoint and fall back to a generic name
        guard let url = URL(string: "https://apis.garmin.com/wellness-api/rest/user/id") else {
            self.athleteName = "Garmin User"
            saveAthleteNameToKeychain("Garmin User")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("GarminService: Invalid response type")
                self.athleteName = "Garmin User"
                saveAthleteNameToKeychain("Garmin User")
                return
            }
            
            print("GarminService: User ID endpoint status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                // Successfully authenticated, but API doesn't provide name
                // Use a generic but authenticated name
                self.athleteName = "Garmin User"
                saveAthleteNameToKeychain("Garmin User")
                print("GarminService: ✅ User authenticated (Garmin API doesn't expose user names)")
            } else {
                print("GarminService: Could not verify user (status: \(httpResponse.statusCode))")
                self.athleteName = "Garmin User"
                saveAthleteNameToKeychain("Garmin User")
            }
            
        } catch {
            print("GarminService: Error verifying user: \(error.localizedDescription)")
            self.athleteName = "Garmin User"
            saveAthleteNameToKeychain("Garmin User")
        }
    }
    
    func uploadCourse(routePoints: [EnhancedRoutePoint], courseName: String, pacingPlan: PacingPlan? = nil, activityType: String = "ROAD_CYCLING") async throws {
        try await refreshTokenIfNeededAsync()
        guard let token = currentTokens?.accessToken else { throw GarminError.notAuthenticated }
        
        let coursesEndpoint = "https://apis.garmin.com/training-api/courses/v1/course"
        
        guard let url = URL(string: coursesEndpoint) else {
            throw GarminError.invalidURL
        }
        
        // Sanitize the name
        let allowedChars = CharacterSet.alphanumerics.union(.whitespaces).union(.init(charactersIn: "-_"))
        let sanitizedName = String(courseName.unicodeScalars.filter(allowedChars.contains))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "-.", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-._ "))
            .prefix(100)
        
        // Calculate course statistics
        let totalDistance = routePoints.last?.distance ?? 0.0
        var elevationGain: Double = 0.0
        var elevationLoss: Double = 0.0
        
        for i in 1..<routePoints.count {
            let currentElev = routePoints[i].elevation ?? 0.0
            let prevElev = routePoints[i-1].elevation ?? 0.0
            let elevDiff = currentElev - prevElev
            
            if elevDiff > 0 {
                elevationGain += elevDiff
            } else {
                elevationLoss += abs(elevDiff)
            }
        }
        
        // Build geoPoints array with power targets
        var geoPointsArray: [[String: Any]] = []
        
        // ✅ Build a lookup map of segment boundaries
        var segmentBoundaries: [(start: Double, end: Double, power: Double)] = []
        if let plan = pacingPlan {
            var cumulativeDistance: Double = 0.0
            for segment in plan.segments {
                let start = cumulativeDistance
                let end = cumulativeDistance + segment.originalSegment.distanceMeters
                segmentBoundaries.append((start, end, segment.targetPower))
                cumulativeDistance = end
            }
            print("GarminService: Built \(segmentBoundaries.count) segment boundaries")
        }
        
        for point in routePoints {
            var geoPoint: [String: Any] = [
                "latitude": point.coordinate.latitude,
                "longitude": point.coordinate.longitude
            ]
            
            // Add elevation if available
            if let elevation = point.elevation {
                geoPoint["elevation"] = elevation
            }
            
            // Check if this point should have a power target marker
            if !segmentBoundaries.isEmpty {
                let pointDistance = point.distance
                
                // Find which segment this point belongs to
                for (start, end, power) in segmentBoundaries {
                    if pointDistance >= start && pointDistance < end {
                        // Only add course point at segment starts (within 50m)
                        let distanceFromStart = abs(pointDistance - start)
                        if distanceFromStart < 50 {
                            let coursePoint: [String: Any] = [
                                "name": "Power \(Int(power))W",
                                "coursePointType": "INFO"
                            ]
                            geoPoint["information"] = coursePoint
                            break
                        }
                    }
                }
            }
            
            geoPointsArray.append(geoPoint)
        }
        
        // Build the course JSON payload
        let coursePayload: [String: Any] = [
            "courseName": sanitizedName,
            "description": "Created by RideWeatherPro with power guidance",
            "distance": totalDistance,
            "elevationGain": elevationGain,
            "elevationLoss": elevationLoss,
            "geoPoints": geoPointsArray,
            "activityType": activityType,
            "coordinateSystem": "WGS84"
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("RideWeatherPro/1.0", forHTTPHeaderField: "User-Agent")
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: coursePayload, options: []) else {
            throw GarminError.invalidJSON
        }
        
        request.httpBody = jsonData
        
        print("GarminService: Uploading course to \(url.absoluteString)")
        print("GarminService: Course name: \(sanitizedName)")
        print("GarminService: Total distance: \(String(format: "%.2f", totalDistance/1000.0))km")
        print("GarminService: Elevation gain: \(String(format: "%.0f", elevationGain))m")
        print("GarminService: Elevation loss: \(String(format: "%.0f", elevationLoss))m")
        print("GarminService: Number of geoPoints: \(geoPointsArray.count)")
        if !segmentBoundaries.isEmpty {
            let powerPointsCount = geoPointsArray.filter { ($0["information"] as? [String: Any]) != nil }.count
            print("GarminService: Power target course points: \(powerPointsCount)")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GarminError.invalidResponse
            }
            
            print("GarminService: Response status: \(httpResponse.statusCode)")
            
//            if let responseBody = String(data: data, encoding: .utf8) {
//                print("GarminService: Response body: \(responseBody)")
//            }
            
            switch httpResponse.statusCode {
            case 200:
                print("GarminService: ✅ Course created successfully!")
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let courseId = json["courseId"] as? Int {
                    print("GarminService: Course ID: \(courseId)")
                }
                
            case 401:
                print("GarminService: User access token doesn't exist")
                throw GarminError.notAuthenticated
                
            case 412:
                print("GarminService: User permission error")
                throw GarminError.insufficientPermissions
                
            case 429:
                print("GarminService: Rate limit exceeded")
                throw GarminError.rateLimitExceeded
                
            default:
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("GarminService: Unexpected status code: \(httpResponse.statusCode)")
                print("GarminService: Response: \(errorMsg)")
                throw GarminError.apiError(statusCode: httpResponse.statusCode, message: errorMsg)
            }
            
        } catch let error as GarminError {
            throw error
        } catch {
            print("GarminService: Network error: \(error.localizedDescription)")
            throw GarminError.networkError(error)
        }
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
            throw GarminError.apiError(statusCode: httpResponse.statusCode, message: responseBody)
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
        case invalidJSON
        case apiError(statusCode: Int, message: String)
        case networkError(Error)
        case insufficientPermissions
        case rateLimitExceeded
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Not authenticated with Garmin. Please reconnect your account."
            case .invalidURL:
                return "Invalid API URL."
            case .invalidResponse:
                return "Invalid response from Garmin."
            case .invalidJSON:
                return "Failed to create JSON payload."
            case .apiError(let code, let message):
                return "Garmin API error (\(code)): \(message)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .insufficientPermissions:
                return "Your app does not have permission to upload courses. Please verify your Courses API access in the Garmin Developer Portal."
            case .rateLimitExceeded:
                return "Rate limit exceeded. Please try again later."
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

