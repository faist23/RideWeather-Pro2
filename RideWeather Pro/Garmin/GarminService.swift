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
    
/*    private */var currentTokens: GarminTokens? {
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
    
    /// This persists across app launches but resets if the app is uninstalled
    private var appUserId: String {
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            return vendorId
        }
        
        // Fallback: Create and store a UUID if vendorId is unavailable
        let fallbackKey = "app_user_id_fallback"
        if let stored = UserDefaults.standard.string(forKey: fallbackKey) {
            return stored
        }
        
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: fallbackKey)
        return newId
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
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "scope", value: "HEALTH_READ ACTIVITY_READ")
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
                    
                    // Link to Supabase
                    // You need to provide your app's user ID here
                    // This could come from your authentication system
                    let appUserId = "c3ac0dc459d0f73055ebb2c9ab7d6fbd" // TODO: Replace with actual user ID
                    
                    do {
                        try await self.linkToSupabase(appUserId: self.appUserId)
                        print("GarminService: ✅ Linked to Supabase successfully")
                    } catch {
                        print("GarminService: ⚠️ Failed to link to Supabase: \(error.localizedDescription)")
                        // Don't fail the whole auth flow if Supabase linking fails
                    }

                } catch {
                    print("GarminService: Token decoding error: \(error)")
                    self.errorMessage = "Token exchange failed. Please try again."
                }
            }
        }.resume()
        
        self.debugTokenScopes() // debug
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
    
    // MARK: - Supabase Integration (Add this section to GarminService.swift)

    /// Link the Garmin user to your app user in Supabase after successful OAuth
    func linkToSupabase(appUserId: String) async throws {
        // Get the Garmin user ID from the wellness API
        guard let garminUserId = try await fetchGarminUserId() else {
            throw GarminError.apiError(statusCode: 0, message: "Could not retrieve Garmin user ID")
        }
        
        print("GarminService: Linking Garmin user \(garminUserId) to app user \(appUserId)")
        
        // Store the mapping in Supabase
        let wellnessService = WellnessDataService()
        try await wellnessService.linkGarminUser(appUserId: appUserId, garminUserId: garminUserId)
        
        print("GarminService: ✅ Successfully linked to Supabase")
    }

    /// Fetch the Garmin user ID from the wellness API
    private func fetchGarminUserId() async throws -> String? {
        try await refreshTokenIfNeededAsync()
        
        guard let token = currentTokens?.accessToken else {
            throw GarminError.notAuthenticated
        }
        
        guard let url = URL(string: "https://apis.garmin.com/wellness-api/rest/user/id") else {
            throw GarminError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarminError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw GarminError.apiError(statusCode: httpResponse.statusCode, message: "Failed to get user ID")
        }
        
        // Parse the response to get user ID
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let userId = json["userId"] as? String {
            return userId
        }
        
        return nil
    }

    func uploadCourse(
        routePoints: [EnhancedRoutePoint],
        courseName: String,
        pacingPlan: PacingPlan? = nil,
        settings: AppSettings? = nil, 
        activityType: String = "ROAD_CYCLING"
    ) async throws {
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
        
        // Calculate course statistics on FULL dataset for accuracy
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
        
        // ✅ OPTIMIZATION: Reduce points to avoid 400 Bad Request (Limit Exceeded)
        // Garmin API limit is ~3500-5000 points. We'll target 3500.
        let optimizedPoints = optimizeRoutePoints(
            routePoints,
            targetCount: 3500,
            boundaries: segmentBoundaries
        )
        print("GarminService: Optimized route from \(routePoints.count) to \(optimizedPoints.count) points")
        
        // ✅ ADD: Calculate time checkpoints if enabled in settings
        var timeCheckpoints: [(distance: Double, time: Double)] = []
        if let plan = pacingPlan, plan.summary.settings.enableTimeCheckpoints {
            let checkpointInterval = plan.summary.settings.timeCheckpointIntervalKm * 1000 // Convert to meters
            var checkpointDistance = checkpointInterval
            
            while checkpointDistance < totalDistance {
                // Calculate elapsed time to this checkpoint
                let elapsedTime = calculateElapsedTime(
                    toDistance: checkpointDistance,
                    pacingPlan: plan
                )
                
                timeCheckpoints.append((distance: checkpointDistance, time: elapsedTime))
                checkpointDistance += checkpointInterval
            }
            
            print("GarminService: Generated \(timeCheckpoints.count) time checkpoints")
        }

        // ✅ NEW: Pre-calculate which point index should get each checkpoint
        // This ensures each checkpoint appears exactly once
        var checkpointAssignments: [Int: (distance: Double, time: Double)] = [:] // pointIndex -> checkpoint
        for checkpoint in timeCheckpoints {
            // Find the single closest point to this checkpoint
            var closestIndex = 0
            var closestDistance = Double.greatestFiniteMagnitude
            
            for (index, point) in optimizedPoints.enumerated() {
                let distance = abs(point.distance - checkpoint.distance)
                if distance < closestDistance {
                    closestDistance = distance
                    closestIndex = index
                }
            }
            
            // Assign this checkpoint to the closest point
            checkpointAssignments[closestIndex] = checkpoint
        }

        print("GarminService: Assigned \(checkpointAssignments.count) checkpoints to specific points")

        // Build geoPoints array with power targets AND time checkpoints
        var geoPointsArray: [[String: Any]] = []

        for (index, point) in optimizedPoints.enumerated() {
            var geoPoint: [String: Any] = [
                "latitude": point.coordinate.latitude,
                "longitude": point.coordinate.longitude
            ]
            
            // Add elevation if available
            if let elevation = point.elevation {
                geoPoint["elevation"] = elevation
            }
            
            let pointDistance = point.distance
            
            // ✅ PRIORITY 1: Check if this specific point was assigned a time checkpoint
            if let checkpoint = checkpointAssignments[index] {
                let hours = Int(checkpoint.time / 3600)
                let minutes = Int((checkpoint.time.truncatingRemainder(dividingBy: 3600)) / 60)
                let seconds = Int(checkpoint.time.truncatingRemainder(dividingBy: 60))
                
                let distanceKm = checkpoint.distance / 1000
                let displayDistance = pacingPlan?.summary.settings.units == .metric ? distanceKm : distanceKm * 0.621371
                let unitSymbol = pacingPlan?.summary.settings.units == .metric ? "km" : "mi"
                
                let coursePoint: [String: Any] = [
                    "name": String(format: "%.1f%@ %02d:%02d:%02d", displayDistance, unitSymbol, hours, minutes, seconds),
                    "coursePointType": "GENERIC"
                ]
                geoPoint["information"] = coursePoint
                
                print("GarminService: Added time checkpoint at point \(index): \(String(format: "%.1f%@ %02d:%02d:%02d", displayDistance, unitSymbol, hours, minutes, seconds))")
            }
            // ✅ PRIORITY 2: If no time checkpoint, check for power targets
            else if !segmentBoundaries.isEmpty {
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

        
        /*        // Build geoPoints array with power targets
        var geoPointsArray: [[String: Any]] = []
        
        for point in optimizedPoints {
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
        } */
        
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
    
    /// Calculates the elapsed time to reach a specific distance in the route
    private func calculateElapsedTime(
        toDistance: Double, // in meters
        pacingPlan: PacingPlan
    ) -> Double {
        var elapsedTime: Double = 0
        
        for segment in pacingPlan.segments {
            let segmentStart = segment.originalSegment.startPoint.distance  // in meters
            let segmentEnd = segment.originalSegment.endPoint.distance      // in meters
            
            if toDistance <= segmentStart {
                // Checkpoint is before this segment starts
                break
            }
            
            if toDistance >= segmentEnd {
                // Entire segment is before the checkpoint
                elapsedTime += segment.estimatedTime
            } else {
                // Checkpoint is within this segment
                let distanceInSegment = toDistance - segmentStart
                let segmentDistance = segmentEnd - segmentStart
                let fractionOfSegment = distanceInSegment / segmentDistance
                elapsedTime += segment.estimatedTime * fractionOfSegment
                break
            }
        }
        
        return elapsedTime
    }
    
    // Helper to downsample points
    private func optimizeRoutePoints(_ points: [EnhancedRoutePoint], targetCount: Int, boundaries: [(start: Double, end: Double, power: Double)]) -> [EnhancedRoutePoint] {
        guard points.count > targetCount else { return points }
        
        var indicesToKeep = Set<Int>()
        indicesToKeep.insert(0)
        indicesToKeep.insert(points.count - 1)
        
        // 1. Preserve points that MUST be kept for segment markers
        // We find the index closest to each segment start distance
        for (start, _, _) in boundaries {
            // Find best matching point
            // Optimization: Assume array is somewhat linear, but binary search or simple scan is safer
            // Given the array is sorted by distance, we could binary search.
            // For simplicity and robustness with 20k points, we can do a distance-based search.
            
            // Find closest index
            // Note: Swift's `min(by:)` on the whole array is slow.
            // We'll use a fast approximation: distance / totalDistance * count
            
            let approximateIndex = Int((start / (points.last?.distance ?? 1)) * Double(points.count))
            let searchRange = max(0, approximateIndex - 500)...min(points.count - 1, approximateIndex + 500)
            
            var bestIdx = approximateIndex
            var bestDiff = Double.greatestFiniteMagnitude
            
            for i in searchRange {
                let diff = abs(points[i].distance - start)
                if diff < bestDiff {
                    bestDiff = diff
                    bestIdx = i
                }
            }
            indicesToKeep.insert(bestIdx)
        }
        
        // 2. Uniformly sample the rest to reach target count
        let step = Double(points.count) / Double(targetCount)
        var current: Double = 0
        while current < Double(points.count) {
            indicesToKeep.insert(Int(current))
            current += step
        }
        
        let sortedIndices = indicesToKeep.sorted()
        return sortedIndices.map { points[$0] }
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
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                return scene.windows.first ?? UIWindow()
            }
            return UIWindow()
        }
        return window
    }
    
    // MARK: - Helpers
/*    private */func refreshTokenIfNeededAsync() async throws {
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
 
    private func logAPIError(_ response: HTTPURLResponse, data: Data, context: String) {
        print("❌ GarminService Error - \(context)")
        print("   Status Code: \(response.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            print("   Response Body: \(responseString)")
        }
        if let headers = response.allHeaderFields as? [String: Any] {
            print("   Headers: \(headers)")
        }
    }

    // ==============================================================================
    // ADD this struct to handle Activity API response format
    // ==============================================================================

    struct GarminActivityAPIResponse: Codable {
        let activityId: Int?
        let activityName: String?
        let activityType: String?
        let startTimeGMT: String?      // ISO8601 format
        let startTimeLocal: String?    // ISO8601 format
        let distance: Double?          // meters
        let duration: Double?          // seconds
        let averageHR: Int?
        let avgPower: Double?
        let calories: Double?
        
        enum CodingKeys: String, CodingKey {
            case activityId
            case activityName
            case activityType
            case startTimeGMT
            case startTimeLocal
            case distance
            case duration
            case averageHR
            case avgPower
            case calories
        }
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
    //-------------------------
    /// Test different Activity API endpoints
    func testActivityEndpoints() async {
        try? await refreshTokenIfNeededAsync()
        
        guard let token = currentTokens?.accessToken else {
            print("❌ Not authenticated")
            return
        }
        
        let endpointsToTry = [
            // Based on course endpoint pattern
            "https://apis.garmin.com/training-api/activity/v1/activity",
            "https://apis.garmin.com/training-api/activity/v1/activities",
            
            // Export endpoints (you have ACTIVITY_EXPORT permission)
            "https://apis.garmin.com/training-api/activity/export",
            "https://apis.garmin.com/training-api/export/activities",
            
            // Historical data (you have HISTORICAL_DATA_EXPORT)
            "https://apis.garmin.com/training-api/historical/activities",
            "https://apis.garmin.com/training-api/historical/data",
            
            // Workout endpoints
            "https://apis.garmin.com/training-api/workout/v2/workout",
            "https://apis.garmin.com/training-api/workout/v2/activities"
        ]
        
        print("\n🔍 Testing Activity Endpoints...\n")
        
        for (index, urlString) in endpointsToTry.enumerated() {
            print("[\(index + 1)/\(endpointsToTry.count)] Testing: \(urlString)")
            
            guard let url = URL(string: urlString) else {
                print("   ❌ Invalid URL\n")
                continue
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("   ❌ Invalid response\n")
                    continue
                }
                
                print("   Status: \(httpResponse.statusCode)")
                
                if let responseString = String(data: data, encoding: .utf8) {
                    print("   Response: \(responseString.prefix(300))...")
                }
                
                if httpResponse.statusCode == 200 {
                    print("   ✅ ✅ ✅ SUCCESS! This endpoint works! ✅ ✅ ✅\n")
                } else {
                    print("   ❌ Failed\n")
                }
                
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
                
            } catch {
                print("   ❌ Error: \(error.localizedDescription)\n")
            }
        }
        
        print("🏁 Testing complete!\n")
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

// MARK: - Activity & Wellness Data Extensions

extension GarminService {
    
    // MARK: - Properties for Data Access
    
    var athleteId: String? {
        // Garmin doesn't expose athlete ID directly in OAuth
        // Use "me" or store from wellness API response
        return "me"
    }
    
    var accessToken: String {
        return currentTokens?.accessToken ?? ""
    }
    
    // MARK: - Activity Fetching
    
    /// 1. NEW: Chunked fetch to respect Garmin's 24h limit per request
    func fetchActivitiesChunked(startDate: Date) async throws {
        let calendar = Calendar.current
        let today = Date()
        
        // Create 24h chunks from startDate until now
        var currentStart = startDate
        var intervals: [(start: Date, end: Date)] = []
        
        while currentStart < today {
            let currentEnd = min(calendar.date(byAdding: .day, value: 1, to: currentStart)!, today)
            intervals.append((currentStart, currentEnd))
            currentStart = currentEnd
        }
        
        print("GarminService: Chunking sync into \(intervals.count) daily requests...")
        
        for (index, interval) in intervals.enumerated() {
            print("GarminService: Fetching chunk \(index + 1)/\(intervals.count)")
            do {
                // Calls the UPDATED fetchActivities below
                let _ = try await fetchActivities(startDate: interval.start, endDate: interval.end)
                // Sleep to avoid rate limiting (429 Too Many Requests)
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            } catch {
                print("⚠️ Failed to fetch chunk \(interval.start): \(error)")
            }
        }
    }
    
    /// 2. UPDATED: Accepts endDate to prevent "time range exceeds 86400s" error
    func fetchActivities(startDate: Date, endDate: Date? = nil) async throws -> [GarminActivity] {
        try await refreshTokenIfNeededAsync()
        
        guard let token = currentTokens?.accessToken else {
            throw GarminError.notAuthenticated
        }
        
        let startSeconds = Int(startDate.timeIntervalSince1970)
        // Fix: Use provided endDate or default to start + 24h (safe default)
        let endSeconds = Int((endDate ?? Date()).timeIntervalSince1970)
        
        // Safety check for the 24h limit
        if (endSeconds - startSeconds) > 86400 {
            print("⚠️ GarminService: Warning - Request range > 24h. API may fail.")
        }
        
        let urlString = "https://apis.garmin.com/wellness-api/rest/activityDetails?uploadStartTimeInSeconds=\(startSeconds)&uploadEndTimeInSeconds=\(endSeconds)"
        
        guard let url = URL(string: urlString) else {
            throw GarminError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarminError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GarminError.apiError(statusCode: httpResponse.statusCode, message: errorMsg)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        // Decode and return activities
        // Note: Check if response is empty array to handle safely
        if let activities = try? decoder.decode([GarminActivity].self, from: data) {
            print("GarminService: Fetched \(activities.count) activities")
            return activities
        } else {
            return [] // Return empty if decode fails (e.g. empty response)
        }
    }
    
    func fetchCourses() async throws -> [GarminCourse] {
        // Not available via OAuth - upload only
        print("ℹ️ Garmin course listing not available via OAuth API")
        return []
/*        try await refreshTokenIfNeededAsync()
        
        guard let token = currentTokens?.accessToken else {
            throw GarminError.notAuthenticated
        }
        
        // ✅ Same endpoint as upload, but GET instead of POST
        let urlString = "https://apis.garmin.com/training-api/courses/v1/course"
        
        guard let url = URL(string: urlString) else {
            throw GarminError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("GarminService: Fetching courses from \(urlString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarminError.invalidResponse
        }
        
        print("GarminService: Response status: \(httpResponse.statusCode)")
        
        if let responseString = String(data: data, encoding: .utf8) {
            print("GarminService: Full response: \(responseString)")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GarminError.apiError(statusCode: httpResponse.statusCode, message: errorMsg)
        }
        
        let decoder = JSONDecoder()
        
        // Try to decode
        do {
            let courses = try decoder.decode([GarminCourse].self, from: data)
            print("GarminService: ✅ Fetched \(courses.count) courses")
            return courses
        } catch {
            print("❌ Decode error: \(error)")
            
            // Log the actual structure
            if let json = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                print("Actual structure received:")
                print(prettyString)
            }
            
            throw error
        }*/
    }
    
    /// Fetch detailed course data including GPS points
    func fetchCourseDetails(courseId: Int) async throws -> [RoutePoint] {
        try await refreshTokenIfNeededAsync()
        
        guard let token = currentTokens?.accessToken else {
            throw GarminError.notAuthenticated
        }
        
        let urlString = "https://apis.garmin.com/training-api/courses/v1/course/\(courseId)"
        
        guard let url = URL(string: urlString) else {
            throw GarminError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarminError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GarminError.apiError(statusCode: httpResponse.statusCode, message: errorMsg)
        }
        
        // Parse the course details
        let courseDetail = try JSONDecoder().decode(GarminCourseDetail.self, from: data)
        
        // Convert geoPoints to RoutePoints
        var routePoints: [RoutePoint] = []
        var cumulativeDistance: Double = 0
        
        for (index, geoPoint) in courseDetail.geoPoints.enumerated() {
            if index > 0 {
                let prevPoint = courseDetail.geoPoints[index - 1]
                let loc1 = CLLocation(latitude: prevPoint.latitude, longitude: prevPoint.longitude)
                let loc2 = CLLocation(latitude: geoPoint.latitude, longitude: geoPoint.longitude)
                cumulativeDistance += loc1.distance(from: loc2)
            }
            
            let routePoint = RoutePoint(
                latitude: geoPoint.latitude,
                longitude: geoPoint.longitude,
                elevation: geoPoint.elevation,
                distance: cumulativeDistance
            )
            routePoints.append(routePoint)
        }
        
        print("GarminService: Fetched \(routePoints.count) GPS points for course \(courseId)")
        return routePoints
    }
    
    // MARK: - Activities API
    
    /// Fetch activities for training load sync
    func fetchActivitiesForTraining(startDate: Date) async throws -> [GarminTrainingActivity] {
        try await refreshTokenIfNeededAsync()
        
        guard let token = currentTokens?.accessToken else {
            throw GarminError.notAuthenticated
        }
        
        let startTimestamp = Int(startDate.timeIntervalSince1970)
        let endTimestamp = Int(Date().timeIntervalSince1970)
        
        let urlString = "https://apis.garmin.com/wellness-api/rest/activityDetails?uploadStartTimeInSeconds=\(startTimestamp)&uploadEndTimeInSeconds=\(endTimestamp)"
        
        guard let url = URL(string: urlString) else {
            throw GarminError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarminError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GarminError.apiError(statusCode: httpResponse.statusCode, message: errorMsg)
        }
        
        let decoder = JSONDecoder()
        let activities = try decoder.decode([GarminTrainingActivity].self, from: data)
        
        print("GarminService: Fetched \(activities.count) activities for training")
        return activities
    }
    
    /// Fetch a specific activity for ride analysis using Activity API
    func fetchActivityDetails(activityId: Int) async throws -> GarminActivityDetail {
        // Not available via OAuth - users should export FIT files
        print("ℹ️ Garmin activity details not available via OAuth API")
        throw GarminError.notAuthenticated // Or create a specific error
/*        try await refreshTokenIfNeededAsync()
        
        guard let token = currentTokens?.accessToken else {
            throw GarminError.notAuthenticated
        }
        
        // Use Activity API endpoint for detailed activity data
        let urlString = "https://apis.garmin.com/activity-service/activity/\(activityId)"
        
        guard let url = URL(string: urlString) else {
            throw GarminError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("GarminService: Fetching activity details for ID \(activityId)...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarminError.invalidResponse
        }
        
        print("GarminService: Activity details response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ GarminService fetchActivityDetails error:")
            print("   Status: \(httpResponse.statusCode)")
            print("   Response: \(errorMsg)")
            throw GarminError.apiError(statusCode: httpResponse.statusCode, message: errorMsg)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        
        // Log response structure
        if let jsonString = String(data: data, encoding: .utf8) {
            print("GarminService: Activity detail structure: \(jsonString.prefix(1000))...")
        }
        
        struct ActivityDetailResponse: Codable {
            let activityId: Int?
            let activityName: String?
            let activityType: String?
            let startTimeGMT: String?
            let durationInSeconds: Int?
            let distanceInMeters: Double?
            let averageHR: Int?
            let maxHR: Int?
            let avgPower: Double?
            let normalizedPower: Double?
            let calories: Double?
            let elevationGain: Double?
            let elevationLoss: Double?
            let samples: [GarminActivitySample]?
        }
        
        do {
            let detail = try decoder.decode(ActivityDetailResponse.self, from: data)
            
            let startTimeInSeconds: Int
            if let startTimeGMT = detail.startTimeGMT {
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: startTimeGMT) {
                    startTimeInSeconds = Int(date.timeIntervalSince1970)
                } else {
                    startTimeInSeconds = Int(Date().timeIntervalSince1970)
                }
            } else {
                startTimeInSeconds = Int(Date().timeIntervalSince1970)
            }
            
            let activityDetail = GarminActivityDetail(
                activityId: detail.activityId ?? activityId,
                activityName: detail.activityName,
                activityType: detail.activityType ?? "Cycling",
                startTimeInSeconds: startTimeInSeconds,
                durationInSeconds: detail.durationInSeconds ?? 0,
                distanceInMeters: detail.distanceInMeters,
                samples: detail.samples,
                averageHeartRateInBeatsPerMinute: detail.averageHR,
                maxHeartRateInBeatsPerMinute: detail.maxHR,
                averagePowerInWatts: detail.avgPower,
                normalizedPowerInWatts: detail.normalizedPower,
                activeKilocalories: detail.calories,
                elevationGainInMeters: detail.elevationGain,
                elevationLossInMeters: detail.elevationLoss
            )
            
            print("GarminService: ✅ Fetched activity details with \(detail.samples?.count ?? 0) samples")
            return activityDetail
            
        } catch {
            print("❌ Failed to decode activity detail: \(error)")
            throw error
        }*/
    }
    
    /// Fetch activity list using Activity API (which you have access to)
    func fetchRecentActivities(limit: Int = 50) async throws -> [GarminActivitySummary] {
        // Not available via OAuth - users should export FIT files
        print("ℹ️ Garmin activity listing not available via OAuth API")
        return []
    }
    
    /*    // ✅ Use Activity API endpoint (not Wellness API)
     // This is for OAuth apps to fetch user's activities
     let urlString = "https://apis.garmin.com/activity-service/activities?limit=\(limit)&start=0"
     
     guard let url = URL(string: urlString) else {
     throw GarminError.invalidURL
     }
     
     var request = URLRequest(url: url)
     request.httpMethod = "GET"
     request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
     
     print("GarminService: Fetching activities from Activity API...")
     print("GarminService: URL: \(urlString)")
     
     let (data, response) = try await URLSession.shared.data(for: request)
     
     guard let httpResponse = response as? HTTPURLResponse else {
     throw GarminError.invalidResponse
     }
     
     print("GarminService: Activity API response status: \(httpResponse.statusCode)")
     
     // Log response for debugging
     if let responseString = String(data: data, encoding: .utf8) {
     print("GarminService: Response preview: \(responseString.prefix(500))...")
     }
     
     guard httpResponse.statusCode == 200 else {
     let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
     print("❌ GarminService Activity API error:")
     print("   Status: \(httpResponse.statusCode)")
     print("   Response: \(errorMsg)")
     throw GarminError.apiError(statusCode: httpResponse.statusCode, message: errorMsg)
     }
     
     // Parse the response
     let decoder = JSONDecoder()
     decoder.keyDecodingStrategy = .convertFromSnakeCase
     decoder.dateDecodingStrategy = .iso8601
     
     do {
     // Try to decode as array directly
     let activities = try decoder.decode([GarminActivityAPIResponse].self, from: data)
     
     // Convert to GarminActivitySummary format and filter cycling
     let summaries = activities
     .filter { activity in
     let type = activity.activityType?.lowercased() ?? ""
     return type.contains("cycling") || type.contains("bike")
     }
     .compactMap { convertActivityAPIToSummary($0) }
     .prefix(limit)
     
     print("GarminService: ✅ Fetched \(summaries.count) cycling activities")
     return Array(summaries)
     
     } catch {
     print("❌ Failed to decode as direct array: \(error)")
     
     // Try wrapped format
     struct ActivitiesWrapper: Codable {
     let activities: [GarminActivityAPIResponse]?
     }
     
     if let wrapped = try? decoder.decode(ActivitiesWrapper.self, from: data),
     let activities = wrapped.activities {
     
     let summaries = activities
     .filter { activity in
     let type = activity.activityType?.lowercased() ?? ""
     return type.contains("cycling") || type.contains("bike")
     }
     .compactMap { convertActivityAPIToSummary($0) }
     .prefix(limit)
     
     print("GarminService: ✅ Fetched \(summaries.count) cycling activities (wrapped)")
     return Array(summaries)
     }
     
     throw error
     }
     }*/
    
    /// Helper to convert Activity API response to our GarminActivitySummary format
    private func convertActivityAPIToSummary(_ activity: GarminActivityAPIResponse) -> GarminActivitySummary? {
        // Activity API returns activityId as Int
        guard let activityId = activity.activityId else {
            return nil
        }
        
        // Parse start time
        let startTimeInSeconds: Int
        if let startTimeGMT = activity.startTimeGMT {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: startTimeGMT) {
                startTimeInSeconds = Int(date.timeIntervalSince1970)
            } else if let startTimeLocal = activity.startTimeLocal {
                // Fallback to local time
                if let date = formatter.date(from: startTimeLocal) {
                    startTimeInSeconds = Int(date.timeIntervalSince1970)
                } else {
                    return nil
                }
            } else {
                return nil
            }
        } else {
            return nil
        }
        
        return GarminActivitySummary(
            activityId: activityId,
            activityName: activity.activityName,
            activityType: activity.activityType ?? "Unknown",
            startTimeInSeconds: startTimeInSeconds,
            durationInSeconds: Int(activity.duration ?? 0),
            distanceInMeters: activity.distance,
            averageHeartRateInBeatsPerMinute: activity.averageHR,
            averagePowerInWatts: activity.avgPower,
            activeKilocalories: activity.calories
        )
    }
}


// MARK: - Garmin Activity Model

struct GarminActivity: Codable {
    let activityId: Int
    let activityName: String
    let activityType: String
    let startTime: Date
    let duration: Int // seconds
    let distance: Double // meters
    let avgPower: Double?
    let avgHeartRate: Double?
    let maxHeartRate: Double?
    let calories: Double?
    
    enum CodingKeys: String, CodingKey {
        case activityId
        case activityName
        case activityType
        case startTime = "startTimeInSeconds"
        case duration = "durationInSeconds"
        case distance = "distanceInMeters"
        case avgPower = "averagePowerInWatts"
        case avgHeartRate = "averageHeartRateInBeatsPerMinute"
        case maxHeartRate = "maxHeartRateInBeatsPerMinute"
        case calories = "activeKilocalories"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activityId = try container.decode(Int.self, forKey: .activityId)
        activityName = try container.decode(String.self, forKey: .activityName)
        activityType = try container.decode(String.self, forKey: .activityType)
        
        // Decode timestamp
        let timestamp = try container.decode(TimeInterval.self, forKey: .startTime)
        startTime = Date(timeIntervalSince1970: timestamp)
        
        duration = try container.decode(Int.self, forKey: .duration)
        distance = try container.decode(Double.self, forKey: .distance)
        avgPower = try container.decodeIfPresent(Double.self, forKey: .avgPower)
        avgHeartRate = try container.decodeIfPresent(Double.self, forKey: .avgHeartRate)
        maxHeartRate = try container.decodeIfPresent(Double.self, forKey: .maxHeartRate)
        calories = try container.decodeIfPresent(Double.self, forKey: .calories)
    }
}

struct GarminCourseDetail: Codable {
    let courseId: Int
    let courseName: String
    let distance: Double
    let elevationGain: Double?
    let elevationLoss: Double?
    let geoPoints: [GarminGeoPoint]
}

struct GarminGeoPoint: Codable {
    let latitude: Double
    let longitude: Double
    let elevation: Double?
}

// MARK: - Activity Models for Training Load

struct GarminTrainingActivity: Codable, Identifiable {
    let activityId: Int
    let activityName: String?
    let activityType: String
    let startTimeInSeconds: Int
    let durationInSeconds: Int
    let distanceInMeters: Double?
    let averageHeartRateInBeatsPerMinute: Int?
    let maxHeartRateInBeatsPerMinute: Int?
    let averagePowerInWatts: Double?
    let normalizedPowerInWatts: Double?
    let activeKilocalories: Double?
    let elevationGainInMeters: Double?
    
    var id: Int { activityId }
    
    var startDate: Date {
        Date(timeIntervalSince1970: TimeInterval(startTimeInSeconds))
    }
}

// MARK: - Activity Models for Ride Analysis

struct GarminActivitySummary: Codable, Identifiable {
    let activityId: Int
    let activityName: String?
    let activityType: String
    let startTimeInSeconds: Int
    let durationInSeconds: Int
    let distanceInMeters: Double?
    let averageHeartRateInBeatsPerMinute: Int?
    let averagePowerInWatts: Double?
    let activeKilocalories: Double?
    
    var id: Int { activityId }
    
    var startDate: Date {
        Date(timeIntervalSince1970: TimeInterval(startTimeInSeconds))
    }
}

struct GarminActivityDetail: Codable {
    let activityId: Int
    let activityName: String?
    let activityType: String
    let startTimeInSeconds: Int
    let durationInSeconds: Int
    let distanceInMeters: Double?
    let samples: [GarminActivitySample]?
    
    // Metrics
    let averageHeartRateInBeatsPerMinute: Int?
    let maxHeartRateInBeatsPerMinute: Int?
    let averagePowerInWatts: Double?
    let normalizedPowerInWatts: Double?
    let activeKilocalories: Double?
    let elevationGainInMeters: Double?
    let elevationLossInMeters: Double?
}

struct GarminActivitySample: Codable {
    let startTimeInSeconds: Int
    let latitude: Double?
    let longitude: Double?
    let elevation: Double?
    let heartRate: Int?
    let power: Double?
    let speed: Double?
    let cadence: Int?
}


//
//  Add this extension to GarminService.swift
//  This manually pulls wellness data from Garmin and saves to Supabase
//

extension GarminService {
    
    /// Manually sync wellness data using Health API (not Wellness API)
    func manualWellnessSync(appUserId: String, days: Int = 7) async throws {
        print("\n🔄 MANUAL GARMIN HEALTH API SYNC")
        print(String(repeating: "=", count: 50))
        
        try await refreshTokenIfNeededAsync()
        
        guard let token = currentTokens?.accessToken else {
            throw GarminError.notAuthenticated
        }
        
        // Get Garmin user ID
        guard let garminUserId = try await fetchGarminUserId() else {
            print("❌ Could not get Garmin user ID")
            throw GarminError.apiError(statusCode: 0, message: "No Garmin user ID")
        }
        
        print("✅ Garmin User ID: \(garminUserId)")
        print("📅 Syncing last \(days) days using Health API...")
        
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDate)!
        
        // Health API uses date strings, not timestamps
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        var allDailies: [GarminDailySummary] = []
        var allSleep: [GarminSleepData] = []
        
        // Fetch data day by day
        var currentDate = startDate
        while currentDate <= endDate {
            let dateString = dateFormatter.string(from: currentDate)
            print("\n📥 Fetching \(dateString)...")
            
            // Fetch daily summary
            if let daily = try await fetchDailySummaryHealthAPI(date: dateString, token: token) {
                allDailies.append(daily)
                print("   ✅ Daily: \(daily.steps ?? 0) steps")
            } else {
                print("   ⚠️ No daily data")
            }
            
            // Fetch sleep data
            if let sleep = try await fetchSleepHealthAPI(date: dateString, token: token) {
                allSleep.append(sleep)
                let totalHours = Double(sleep.sleepTimeSeconds ?? 0) / 3600
                print("   ✅ Sleep: \(String(format: "%.1f", totalHours))h")
            } else {
                print("   ⚠️ No sleep data")
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s delay
        }
        
        print("\n✅ Fetched from Garmin Health API:")
        print("   - Daily summaries: \(allDailies.count)")
        print("   - Sleep records: \(allSleep.count)")
        
        // Save to Supabase
        let wellnessService = WellnessDataService()
        
        print("\n💾 Saving to Supabase...")
        
        // Save dailies
        for daily in allDailies {
            do {
                try await wellnessService.saveDailySummary(
                    appUserId: appUserId,
                    garminUserId: garminUserId,
                    summary: daily
                )
                print("   ✅ Saved daily: \(daily.calendarDate)")
            } catch {
                print("   ❌ Failed to save daily \(daily.calendarDate): \(error)")
            }
        }
        
        // Save sleep
        for sleep in allSleep {
            do {
                try await wellnessService.saveSleepData(
                    appUserId: appUserId,
                    garminUserId: garminUserId,
                    sleep: sleep
                )
                print("   ✅ Saved sleep: \(sleep.calendarDate)")
            } catch {
                print("   ❌ Failed to save sleep \(sleep.calendarDate): \(error)")
            }
        }
        
        print("\n✅ MANUAL SYNC COMPLETE")
        print(String(repeating: "=", count: 50))
    }
    
    // MARK: - Health API Endpoints
    
    /// Fetch daily summary using Health API
    private func fetchDailySummaryHealthAPI(date: String, token: String) async throws -> GarminDailySummary? {
        // Health API endpoint format: /api/health/v1/user/summaries/{date}
        let urlString = "https://apis.garmin.com/api/health/v1/user/summaries/\(date)"
        
        guard let url = URL(string: urlString) else {
            throw GarminError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("   📡 Health API: \(urlString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarminError.invalidResponse
        }
        
        print("   Response: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            if let responseString = String(data: data, encoding: .utf8) {
                print("   Error: \(responseString)")
            }
            return nil // No data for this date
        }
        
        // Parse Health API response
        struct HealthAPIDailySummary: Codable {
            let summaryDate: String?
            let totalSteps: Int?
            let totalDistanceMeters: Int?
            let activeTimeSeconds: Int?
            let activeKilocalories: Int?
            let bmrKilocalories: Int?
            let restingHeartRate: Int?
            
            enum CodingKeys: String, CodingKey {
                case summaryDate, totalSteps, totalDistanceMeters, activeTimeSeconds,
                     activeKilocalories, bmrKilocalories, restingHeartRate
            }
        }
        
        let decoder = JSONDecoder()
        let healthSummary = try decoder.decode(HealthAPIDailySummary.self, from: data)
        
        // Convert to our format
        return GarminDailySummary(
            calendarDate: healthSummary.summaryDate ?? date,
            steps: healthSummary.totalSteps,
            distanceInMeters: healthSummary.totalDistanceMeters,
            activeTimeInSeconds: healthSummary.activeTimeSeconds,
            activeKilocalories: healthSummary.activeKilocalories,
            bmrKilocalories: healthSummary.bmrKilocalories,
            stressLevel: nil,
            bodyBatteryChargedValue: nil,
            bodyBatteryDrainedValue: nil,
            bodyBatteryHighestValue: nil,
            bodyBatteryLowestValue: nil,
            restingHeartRate: healthSummary.restingHeartRate,
            hrVariability: nil
        )
    }
    
    /// Fetch sleep data using Health API
    private func fetchSleepHealthAPI(date: String, token: String) async throws -> GarminSleepData? {
        // Health API endpoint: /api/health/v1/user/sleeps/{date}
        let urlString = "https://apis.garmin.com/api/health/v1/user/sleeps/\(date)"
        
        guard let url = URL(string: urlString) else {
            throw GarminError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("   📡 Health API: \(urlString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GarminError.invalidResponse
        }
        
        print("   Response: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            if let responseString = String(data: data, encoding: .utf8) {
                print("   Error: \(responseString)")
            }
            return nil // No data for this date
        }
        
        // Parse Health API response
        struct HealthAPISleep: Codable {
            let sleepDate: String?
            let totalSleepSeconds: Int?
            let deepSleepSeconds: Int?
            let lightSleepSeconds: Int?
            let remSleepSeconds: Int?
            let awakeSleepSeconds: Int?
            
            enum CodingKeys: String, CodingKey {
                case sleepDate, totalSleepSeconds, deepSleepSeconds, lightSleepSeconds,
                     remSleepSeconds, awakeSleepSeconds
            }
        }
        
        let decoder = JSONDecoder()
        let healthSleep = try decoder.decode(HealthAPISleep.self, from: data)
        
        // Convert to our format
        return GarminSleepData(
            calendarDate: healthSleep.sleepDate ?? date,
            sleepTimeSeconds: healthSleep.totalSleepSeconds,
            deepSleepSeconds: healthSleep.deepSleepSeconds,
            lightSleepSeconds: healthSleep.lightSleepSeconds,
            remSleepSeconds: healthSleep.remSleepSeconds,
            awakeSleepSeconds: healthSleep.awakeSleepSeconds,
            sleepQualityScore: nil
        )
    }
}

extension GarminService {
    /// Debug function to check what scopes the current token has
    func debugTokenScopes() {
        guard let tokens = currentTokens else {
            print("❌ No token available")
            return
        }
        
        print("\n🔍 TOKEN DEBUG INFO:")
        print("   Access Token: \(tokens.accessToken.prefix(20))...")
        print("   Expires: \(Date(timeIntervalSince1970: tokens.expiresAt))")
        
        // Decode JWT to see scopes (if token is JWT format)
        let parts = tokens.accessToken.components(separatedBy: ".")
        if parts.count == 3, let payloadData = base64UrlDecode(parts[1]) {
            if let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                print("   Token Payload:")
                if let scope = json["scope"] as? String {
                    print("   ✅ Scopes: \(scope)")
                } else if let scopes = json["scopes"] as? [String] {
                    print("   ✅ Scopes: \(scopes.joined(separator: ", "))")
                } else {
                    print("   ⚠️ No scope field found in token")
                }
            }
        }
    }
    
    private func base64UrlDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let length = Double(base64.lengthOfBytes(using: .utf8))
        let requiredLength = 4 * ceil(length / 4.0)
        let paddingLength = requiredLength - length
        if paddingLength > 0 {
            let padding = "".padding(toLength: Int(paddingLength), withPad: "=", startingAt: 0)
            base64 += padding
        }
        return Data(base64Encoded: base64)
    }
}
