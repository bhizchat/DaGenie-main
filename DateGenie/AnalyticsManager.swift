//  AnalyticsManager.swift
//  DateGenie
//
//  Centralised wrapper around Firebase Analytics + optional Firestore logging.
//  Handles:
//  • Session start / end events
//  • Generic event logging
//  • User properties (install_date, sub_tier)
//  Feel free to expand with more specialised helpers.

import Foundation
import FirebaseAnalytics
import FirebaseFirestore

final class AnalyticsManager {
    static let shared = AnalyticsManager()
    private init() { }

    private let db = Firestore.firestore()
    private var sessionId: String?

    // MARK: - Public API

    /// Call once per app launch when the user state is known.
    func configure(userId: String?, subscriptionTier: String?) {
        if let userId {
            Analytics.setUserID(userId)
        }
        if let subscriptionTier {
            Analytics.setUserProperty(subscriptionTier, forName: "sub_tier")
        }

        // Set install_date only once
        let installKey = "dg_install_date"
        if UserDefaults.standard.string(forKey: installKey) == nil {
            let installDate = ISO8601DateFormatter().string(from: Date())
            UserDefaults.standard.set(installDate, forKey: installKey)
            Analytics.setUserProperty(installDate, forName: "install_date")
        } else if let installDate = UserDefaults.standard.string(forKey: installKey) {
            Analytics.setUserProperty(installDate, forName: "install_date")
        }
    }

    /// Begin a new analytics session.
    func startSession() {
        sessionId = UUID().uuidString
        Analytics.logEvent(AnalyticsEventAppOpen, parameters: [
            "session_id": sessionId ?? "unknown"
        ])
        // Optional: Persist session start to Firestore for detailed timeline
        logToFirestore(name: "session_start", parameters: ["session_id": sessionId ?? "unknown"])
    }

    /// End the current session.
    func endSession() {
        guard let sessionId else { return }
        Analytics.logEvent("session_end", parameters: ["session_id": sessionId])
        logToFirestore(name: "session_end", parameters: ["session_id": sessionId])
        self.sessionId = nil
    }

    /// Generic event logger
    func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        Analytics.logEvent(name, parameters: parameters)
        logToFirestore(name: name, parameters: parameters)
    }

    // MARK: - Private helpers
    private func logToFirestore(name: String, parameters: [String: Any]? = nil) {
        var data: [String: Any] = [
            "event": name,
            "timestamp": FieldValue.serverTimestamp(),
            "session_id": sessionId ?? NSNull()
        ]
        if let parameters { data.merge(parameters) { $1 } }
        db.collection("analytics_logs").addDocument(data: data)
    }
}
