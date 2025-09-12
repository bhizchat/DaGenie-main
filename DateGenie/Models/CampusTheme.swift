//  CampusTheme.swift
//  Model representing a campus adventure theme returned from backend

import Foundation

struct Missions: Codable {
    let gamesToPlay: [String]
    let tasks: [String]? // optional, older payloads may not include it
    let checkpointPhoto: String

    /// Returns the task string for a node, stripping the leading "Task:" prefix if present.
    func task(for index: Int) -> String {
        if let tasks = tasks, index < tasks.count {
            return clean(tasks[index])
        }
        // Fallback 1: separate list of tasks embedded in gamesToPlay entries that *contain* "Task:" anywhere (some payloads mix them)
        let taskLines = gamesToPlay.compactMap { line -> String? in
            guard let range = line.range(of: "Task:", options: [.caseInsensitive]) else { return nil }
            return String(line[range.lowerBound...]) // from "Task:" to end
        }
        if index < taskLines.count {
            return clean(taskLines[index])
        }
        return "Complete the mission"
    }

    func clean(_ task: String) -> String {
        // Add your cleaning logic here
        return task.replacingOccurrences(of: "Task:", with: "", options: [.caseInsensitive])
    }
}

struct CampusTheme: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let venueName: String
    let photoUrl: String
    let distanceMeters: Int?
    let address: String?
    // Curated text lines from backend, e.g. [Action text, "Photo Idea: ..."]
    let missionLines: [String]?
    let missions: Missions
}

#if DEBUG
extension CampusTheme {
    static let sample = CampusTheme(
        id: "sample",
        title: "Sample Adventure",
        venueName: "Sample Venue",
        photoUrl: "",
        distanceMeters: 100,
        address: "123 College Ave, City",
        missionLines: [
            "Students typically stop here for drinks with friends.",
            "Photo Idea: Pose by the entrance sign."
        ],
        missions: Missions(
            gamesToPlay: ["Play Rock, Paper and Scissors. Loser does a TikTok dance.",
                          "Play Rock, Paper and Scissors. Loser buys something under $5."],
            tasks: ["Task: Take a glamorous food photo of your partner posing like it's a high-fashion shoot.",
                    "Task: Interview a stranger about their favorite campus memory and film it."],
            checkpointPhoto: "Checkpoint Photo: Take a selfie by the entrance"
        )
    )
}
#endif

// Equatable conformance – compare by id (kept outside DEBUG so it exists in all builds)
extension CampusTheme {
    static func == (lhs: CampusTheme, rhs: CampusTheme) -> Bool {
        lhs.id == rhs.id
    }
}
