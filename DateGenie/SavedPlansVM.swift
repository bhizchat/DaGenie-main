//  SavedPlansVM.swift
//  DateGenie
//
//  Keeps track of user's saved date plans in Firestore

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseAnalytics

@MainActor
class SavedPlansVM: ObservableObject {
    @Published var savedIds: Set<String> = []
    @Published var savedPlans: [DatePlan] = []
    private var listener: ListenerRegistration?

    init() { listen() }
    deinit { listener?.remove() }

    private func listen() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener = Firestore.firestore()
            .collection("users").document(uid)
            .collection("savedPlans")
            .addSnapshotListener { [weak self] snap, _ in
                guard let self = self else { return }
                guard let docs = snap?.documents else { return }
                self.savedIds = Set(docs.map { $0.documentID })
                let decoder = JSONDecoder()
                self.savedPlans = docs.compactMap { doc in
                    guard let json = try? JSONSerialization.data(withJSONObject: doc.data()) else { return nil }
                    return try? decoder.decode(DatePlan.self, from: json)
                }
            }
    }

    func toggleSave(plan: DatePlan) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = Firestore.firestore()
            .collection("users").document(uid)
            .collection("savedPlans").document(plan.id)
        if savedIds.contains(plan.id) {
            ref.delete()
        } else {
            // Encode plan -> [String: Any]
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(plan),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var copy = obj
                copy["savedAt"] = Date().timeIntervalSince1970 * 1000
                ref.setData(copy) { error in
                    if let err = error {
                        print("❌ Failed to save plan: \(err.localizedDescription)")
                    } else {
                        AnalyticsManager.shared.logEvent("plan_saved", parameters: [
                            "plan_id": plan.id
                        ])
                    }
                }
            // Optimistic local update so UI reflects immediately
            savedIds.insert(plan.id)
            savedPlans.append(plan)
            }
        }
    }
}
