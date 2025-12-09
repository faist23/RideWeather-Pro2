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
            URLQueryItem(name: "scope", value: "WELLNESS_READ ACTIVITY_READ")
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
    
    /// Fetches activities from Garmin Connect
    func fetchActivities(startDate: Date) async throws -> [GarminActivity] {
        try await refreshTokenIfNeededAsync()
        
        guard let token = currentTokens?.accessToken else {
            throw GarminError.notAuthenticated
        }
        
        let formatter = ISO8601DateFormatter()
        let startString = formatter.string(from: startDate)
        
        // Garmin Connect API endpoint for activities
        let urlString = "https://apis.garmin.com/wellness-api/rest/activityDetails?uploadStartTimeInSeconds=\(Int(startDate.timeIntervalSince1970))&uploadEndTimeInSeconds=\(Int(Date().timeIntervalSince1970))"
        
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
        let activities = try decoder.decode([GarminActivity].self, from: data)
        
        print("GarminService: Fetched \(activities.count) activities")
        return activities
    }

    /// Fetch all courses from Garmin
    func fetchCourses() async throws -> [GarminCourse] {
        try await refreshTokenIfNeededAsync()
        
        guard let token = currentTokens?.accessToken else {
            throw GarminError.notAuthenticated
        }
        
        let urlString = "https://apis.garmin.com/training-api/courses/v1/courses"
        
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
        let courses = try decoder.decode([GarminCourse].self, from: data)
        
        print("GarminService: Fetched \(courses.count) courses")
        return courses
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
    
    /// Fetch a specific activity for ride analysis
    func fetchActivityDetails(activityId: Int) async throws -> GarminActivityDetail {
        try await refreshTokenIfNeededAsync()
        
        guard let token = currentTokens?.accessToken else {
            throw GarminError.notAuthenticated
        }
        
        let urlString = "https://apis.garmin.com/wellness-api/rest/activityDetails/\(activityId)"
        
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
        
        let activity = try JSONDecoder().decode(GarminActivityDetail.self, from: data)
        
        print("GarminService: Fetched activity details for \(activityId)")
        return activity
    }
    
    /// Fetch activity list for ride analysis import
    func fetchRecentActivities(limit: Int = 50) async throws -> [GarminActivitySummary] {
        try await refreshTokenIfNeededAsync()
        
        guard let token = currentTokens?.accessToken else {
            throw GarminError.notAuthenticated
        }
        
        // Get activities from the last 30 days
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
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
        var activities = try decoder.decode([GarminActivitySummary].self, from: data)
        
        // Filter to cycling activities and limit
        activities = activities
            .filter { $0.activityType.lowercased().contains("cycling") || $0.activityType.lowercased().contains("bike") }
            .prefix(limit)
            .map { $0 }
        
        print("GarminService: Fetched \(activities.count) recent cycling activities")
        return activities
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
