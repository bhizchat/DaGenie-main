//  HuntModels.swift
//  DateGenie
//
//  Created as part of Sprint 1 scaffolding.
//
import Foundation
import FirebaseFirestore

// MARK: - Clue (partial – only what the selector needs for now)
struct Clue: Codable {
    var order: Int
    var type: String
    var text: String
    var lat: Double
    var lng: Double
    var mobility: String?
}

// MARK: - HuntTemplate
enum CityCampus: String, Codable {
    case campusA = "Campus A"
    case campusB = "Campus B"
}

struct HuntTemplate: Identifiable, Codable {
    var id: String // Firestore doc ID

    var title: String
    var city: CityCampus
    var durationMin: Int
    var budgetUSD: Int
    var clues: [Clue]

    // Computed helpers
    var heroDurationString: String { "~\(durationMin) min" }
    var heroBudgetString: String { budgetUSD == 0 ? "Free" : "$\(budgetUSD)" }
}

// MARK: - HuntPrefs
enum IndoorOutdoor: String, Codable, CaseIterable {
    case indoor, outdoor, either
}

struct HuntPrefs: Codable {
    var indoorOutdoor: IndoorOutdoor = .either
    var interests: [String] = []
    var maxBudget: Int = 20
    var travelRadiusKm: Double = 2
    var lowMobility: Bool = false
    var firstDateMode: Bool = false

    var travelRadiusMeters: Double { travelRadiusKm * 1000 }
}
