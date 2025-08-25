//  SubscriptionGate.swift
//  DateGenie
//
//  Lightweight helpers to persist/read the requiresSubscriptionForGeneration flag.

import Foundation
import FirebaseAuth
import FirebaseFirestore

enum SubscriptionGate {
    static func setRequireForGenerationTrue() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        do {
            try await db.collection("users").document(uid).setData([
                "subscription": [
                    "requiresSubscriptionForGeneration": true
                ]
            ], merge: true)
        } catch {
            print("[SubscriptionGate] set flag error: \(error)")
        }
    }

    static func getRequireForGeneration() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            let sub = (snap.data()? ["subscription"]) as? [String: Any]
            return (sub?["requiresSubscriptionForGeneration"] as? Bool) ?? false
        } catch {
            print("[SubscriptionGate] read flag error: \(error)")
            return false
        }
    }
}


