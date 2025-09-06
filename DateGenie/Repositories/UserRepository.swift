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
    // Local cache path for the user's processed transparent logo PNG (Documents URL path)
    @AppStorage("cachedBrandLogoPath") private var cachedBrandLogoPath: String = ""
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
            let brand = data["brandLogoURL"] as? String
            let p = UserProfileData(photoURL: url, username: uname, firstName: first, lastName: last, displayName: disp, brandLogoURL: brand)
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

    // MARK: - Brand logo helpers
    func updateBrandLogoURL(_ url: String?) async {
        self.profile.brandLogoURL = url
        if let blob = try? JSONEncoder().encode(self.profile) { cachedProfileData = blob }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var data: [String: Any] = [:]
        if let url { data["brandLogoURL"] = url } else { data["brandLogoURL"] = FieldValue.delete() }
        try? await db.collection("users").document(uid).setData(data, merge: true)
    }

    /// Preferred local cached file URL for the processed brand logo, if present.
    func brandLogoLocalURL() -> URL? {
        // Prefer explicit cached path if valid
        if !cachedBrandLogoPath.isEmpty {
            let url = URL(fileURLWithPath: cachedBrandLogoPath)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        // Next, if profile has a file URL string
        if let s = profile.brandLogoURL, let u = URL(string: s), u.isFileURL {
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        // Fallback to onboarding's stored path if present
        if let path = UserDefaults.standard.string(forKey: "onboarding.logoPath"), !path.isEmpty {
            let u = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// Save a transparent PNG to Documents as brand_logo.png and update caches/profile.
    @discardableResult
    func saveBrandLogoPNG(_ image: UIImage) async -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dest = docs.appendingPathComponent("brand_logo.png")
        do {
            if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: dest) }
            // If input does not contain alpha, try to synthesize transparency via BackgroundRemoval
            let finalImage: UIImage = {
                if imageHasAlpha(image) { return image }
                var cutout: UIImage? = nil
                let sema = DispatchSemaphore(value: 0)
                BackgroundRemoval.removeBackground(from: image) { out in cutout = out; sema.signal() }
                sema.wait()
                return cutout ?? image
            }()
            if let data = finalImage.pngData() {
                try data.write(to: dest, options: .atomic)
                cachedBrandLogoPath = dest.path
                await updateBrandLogoURL(dest.absoluteString)
                return dest
            }
        } catch {
            print("[UserRepository] saveBrandLogoPNG error: \(error.localizedDescription)")
        }
        return nil
    }

    private func imageHasAlpha(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let alpha = cg.alphaInfo
        return alpha == .first || alpha == .last || alpha == .premultipliedFirst || alpha == .premultipliedLast
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
