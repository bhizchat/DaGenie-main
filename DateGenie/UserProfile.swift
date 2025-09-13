//  UserProfile.swift
//  DateGenie
//
//  Holds live user stats such as romancePoints.

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
final class UserProfile: ObservableObject {
    @Published var romancePoints: Int = 0

    private var listener: ListenerRegistration?

    init() {
        listen()
    }

    deinit { listener?.remove() }

    private func listen() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = Firestore.firestore()
            .collection("users").document(uid)
            .collection("stats").document("aggregates")
        listener = ref.addSnapshotListener { [weak self] snap, _ in
            guard let data = snap?.data() else { return }
            self?.romancePoints = data["romancePoints"] as? Int ?? 0
        }
    }
}
