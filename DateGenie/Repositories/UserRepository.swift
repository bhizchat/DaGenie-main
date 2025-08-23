//  UserRepository.swift
//  DateGenie
//
//  Persists HuntPrefs to Firestore and caches via AppStorage.
//
import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

@MainActor
final class UserRepository: ObservableObject {
    static let shared = UserRepository()
    private init() {}

    @AppStorage("cachedPrefs") private var cachedPrefsData: Data = Data()
    @AppStorage("cachedProfile") private var cachedProfileData: Data = Data()
    @Published private(set) var prefs: HuntPrefs = HuntPrefs()

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    // MARK: - Profile (photoURL)
    @Published private(set) var profile: UserProfileData = UserProfileData()

    func loadProfile() async {
        if let decoded = try? JSONDecoder().decode(UserProfileData.self, from: cachedProfileData) {
            self.profile = decoded
        }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if let snap = try? await db.collection("users").document(uid).getDocument(),
           let data = snap.data() {
            let url = data["photoURL"] as? String
            let uname = data["username"] as? String
            let first = data["firstName"] as? String
            let last = data["lastName"] as? String
            let disp = data["displayName"] as? String
            let p = UserProfileData(photoURL: url, username: uname, firstName: first, lastName: last, displayName: disp)
            self.profile = p
            if let blob = try? JSONEncoder().encode(p) { cachedProfileData = blob }
        }
    }
    func updatePhotoURL(_ url: String?) async {
        self.profile.photoURL = url
        if let blob = try? JSONEncoder().encode(self.profile) { cachedProfileData = blob }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var data: [String: Any] = [:]
        if let url { data["photoURL"] = url } else { data["photoURL"] = FieldValue.delete() }
        try? await db.collection("users").document(uid).setData(data, merge: true)
    }
    func updateUsername(_ name: String) async {
        self.profile.username = name
        if let blob = try? JSONEncoder().encode(self.profile) { cachedProfileData = blob }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("users").document(uid).setData(["username": name], merge: true)
    }

    func loadPrefs() async throws {
        // 1. Use AppStorage cache if available (offline support)
        if let decoded = try? JSONDecoder().decode(HuntPrefs.self, from: cachedPrefsData) {
            self.prefs = decoded
        }

        // 2. Try network fetch
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let doc = try await db.collection("users").document(uid).getDocument()
        if let remotePrefs = try? doc.data(as: HuntPrefs.self) {
            self.prefs = remotePrefs
            cache(prefs: remotePrefs)
        }
    }

    func updatePrefs(_ newPrefs: HuntPrefs) async throws {
        self.prefs = newPrefs
        cache(prefs: newPrefs)
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(uid).setData(from: newPrefs, merge: true)
    }

    private func cache(prefs: HuntPrefs) {
        if let data = try? JSONEncoder().encode(prefs) {
            cachedPrefsData = data
        }
    }
}
