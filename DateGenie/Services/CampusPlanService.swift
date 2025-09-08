//  CampusPlanService.swift
//  Handles network call to Cloud Function generateCampusPlans

import Foundation
@preconcurrency import FirebaseFunctions

@MainActor
final class CampusPlanService {
    static let shared = CampusPlanService()
    private let functions = Functions.functions()

    func generatePlans(college: String, latitude: Double, longitude: Double, mood: String, timeOfDay: String, maxDistanceMeters: Int) async throws -> [CampusTheme] {
        let data: [String: Any] = [
            "college": college,
            "latitude": latitude,
            "longitude": longitude,
            "mood": mood,
            "timeOfDay": timeOfDay,
            "maxDistanceMeters": maxDistanceMeters
        ]
        let result = try await functions.httpsCallable("generateCampusPlans").call(data)
        guard let dict = result.data as? [String: Any] else {
            print("❌ Failed to cast result.data to [String: Any]")
            return []
        }
        guard let arr = dict["themes"] as? [[String: Any]] else {
            print("❌ Failed to cast dict['themes'] to [[String: Any]]")
            print("📊 Result data: \(dict)")
            return []
        }
        print("✅ Found \(arr.count) themes")
        let json = try JSONSerialization.data(withJSONObject: arr)
        do {
            return try JSONDecoder().decode([CampusTheme].self, from: json)
        } catch {
            if let jsonString = String(data: json, encoding: .utf8) {
                print("❌ JSON decode failed: \(error). JSON string: \n\(jsonString)")
            } else {
                print("❌ JSON decode failed: \(error). Could not convert JSON to string")
            }
            throw error
        }
    }

    // keep paged helper around if we re-enable later (unused now)
}
