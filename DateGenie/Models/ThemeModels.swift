//  ThemeModels.swift
//  DateGenie
//  Core structs for the new theme-based scavenger hunt flow.
//
import Foundation
import SwiftUI

struct Mission: Identifiable, Codable {
    enum Kind: String, Codable, CaseIterable {
        case task = "Task"
        case aiGame = "AI Game"
        case trivia = "Trivia"
        case photo = "Photo"
    }

    var id = UUID()
    var kind: Kind
    var prompt: String
    var points: Int
}

struct AdventureTheme: Identifiable, Codable {
    var id: String // Firestore doc ID
    var title: String
    var venueName: String
    var venueImageURL: String
    var basePoints: Int
    var missions: [Mission]
}

// Dummy placeholder for previews
extension AdventureTheme {
    static let sample: AdventureTheme = .init(
        id: "demo",
        title: "Exploring Art at SFMOMA",
        venueName: "SFMOMA",
        venueImageURL: "https://picsum.photos/400/300",
        basePoints: 24,
        missions: Mission.Kind.allCases.map { Mission(kind: $0, prompt: "Sample", points: 5) }
    )
}
