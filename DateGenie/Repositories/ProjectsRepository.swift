import Foundation
import FirebaseFirestore
import FirebaseStorage
import AVFoundation
import UIKit

final class ProjectsRepository: ObservableObject {
    static let shared = ProjectsRepository()
    private init() {}

    @Published private(set) var projects: [Project] = []

    private var db: Firestore { Firestore.firestore() }
    private var storage: Storage { Storage.storage() }

    func load(userId: String) async {
        if FeatureFlags.disableProjectSaving {
            await MainActor.run { self.projects = [] }
            return
        }
        do {
            let snap = try await db.collection("users").document(userId).collection("projects").order(by: "createdAt", descending: true).getDocuments()
            let results: [Project] = snap.documents.compactMap { doc in
                let data = doc.data()
                let id = doc.documentID
                let name = data["name"] as? String ?? "Untitled"
                let ts = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                let vidStr = data["videoURL"] as? String
                let thStr = data["thumbURL"] as? String
                let storyboardId = data["storyboardId"] as? String
                let cur = data["currentSceneIndex"] as? Int
                let total = data["totalScenes"] as? Int
                return Project(id: id, name: name, createdAt: ts, videoURL: vidStr.flatMap(URL.init), thumbURL: thStr.flatMap(URL.init), isDraft: (data["isDraft"] as? Bool) ?? true, lastEditedAt: (data["lastEditedAt"] as? Timestamp)?.dateValue(), draftThumbnailLocalPath: nil, durationSec: data["durationSec"] as? Double, clipCount: data["clipCount"] as? Int, storyboardId: storyboardId, currentSceneIndex: cur, totalScenes: total)
            }
            await MainActor.run { self.projects = results }
        } catch {
            print("[ProjectsRepository] load error: \(error)")
        }
    }

    func create(userId: String, name: String = "Start Video") async -> Project? {
        if FeatureFlags.disableProjectSaving {
            // Do not persist; return an ephemeral project model for flows that expect one
            let now = Date()
            let model = Project(id: UUID().uuidString, name: name, createdAt: now, videoURL: nil, thumbURL: nil, isDraft: true, lastEditedAt: now, draftThumbnailLocalPath: nil)
            await MainActor.run { self.projects.insert(model, at: 0) }
            return model
        }
        let id = UUID().uuidString
        let doc = db.collection("users").document(userId).collection("projects").document(id)
        let now = Date()
        let model = Project(id: id, name: name, createdAt: now, videoURL: nil, thumbURL: nil, isDraft: true, lastEditedAt: now, draftThumbnailLocalPath: nil)
        do {
            // Use server timestamp to satisfy Firestore rules (createdAt == request.time)
            try await doc.setData([
                "name": model.name,
                "createdAt": FieldValue.serverTimestamp()
            ])
            await MainActor.run { self.projects.insert(model, at: 0) }
            return model
        } catch {
            print("[ProjectsRepository] create error: \(error)")
            return nil
        }
    }

    // MARK: - Draft helpers
    func createDraft(userId: String, name: String = "Untitled") async -> Project? {
        return await create(userId: userId, name: name)
    }

    func uploadDraftThumbnail(userId: String, projectId: String, image: UIImage) async {
        if FeatureFlags.disableProjectSaving { return }
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let path = "users/\(userId)/projects/\(projectId)/thumb.jpg"
        let ref = storage.reference(withPath: path)
        do {
            _ = try await ref.putDataAsync(data)
            let url = try await ref.downloadURL()
            try await db.collection("users").document(userId).collection("projects").document(projectId).updateData([
                "thumbURL": url.absoluteString
            ])
            await MainActor.run {
                if let i = self.projects.firstIndex(where: { $0.id == projectId }) {
                    self.projects[i].thumbURL = url
                }
            }
        } catch {
            print("[ProjectsRepository] uploadDraftThumbnail error: \(error)")
        }
    }

    // Attach a remote video URL (already hosted) to an existing project
    func attachVideoURL(userId: String, projectId: String, remoteURL: URL) async {
        if FeatureFlags.disableProjectSaving { return }
        do {
            try await db.collection("users").document(userId).collection("projects").document(projectId).updateData([
                "videoURL": remoteURL.absoluteString
            ])
            await MainActor.run {
                if let i = self.projects.firstIndex(where: { $0.id == projectId }) {
                    self.projects[i].videoURL = remoteURL
                }
            }
        } catch {
            print("[ProjectsRepository] attachVideoURL error: \(error)")
        }
    }

    // MARK: - Naming helpers
    /// Returns a sequential name like "Start Video (N)" based on existing projects.
    @MainActor
    func nextNewVideoName() -> String {
        let base = "Start Video"
        var maxN = 0
        for p in projects {
            let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name == base { maxN = max(maxN, 1); continue }
            if let r = try? NSRegularExpression(pattern: "^Start\\s+Video\\s*\\((\\d+)\\)$", options: .caseInsensitive) {
                let ns = name as NSString
                if let m = r.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 {
                    let g = ns.substring(with: m.range(at: 1))
                    if let n = Int(g) { maxN = max(maxN, n) }
                }
            }
        }
        let next = maxN + 1
        return "\(base) (\(next))"
    }

    // MARK: - Progress updates
    func updateProgress(userId: String, projectId: String, durationSec: Double, clipCount: Int) async {
        if FeatureFlags.disableProjectSaving { return }
        do {
            try await db.collection("users").document(userId).collection("projects").document(projectId).updateData([
                "durationSec": durationSec,
                "clipCount": clipCount,
                "lastEditedAt": FieldValue.serverTimestamp()
            ])
            await MainActor.run {
                if let i = self.projects.firstIndex(where: { $0.id == projectId }) {
                    // Keep local mirror lightweight; we won't store these fields in the model yet
                    // (UI can re-load from Firestore on next open if needed)
                }
            }
        } catch {
            print("[ProjectsRepository] updateProgress error: \(error)")
        }
    }

    func rename(userId: String, projectId: String, to newName: String) async {
        if FeatureFlags.disableProjectSaving { return }
        do { try await db.collection("users").document(userId).collection("projects").document(projectId).updateData(["name": newName])
            await MainActor.run {
                if let i = self.projects.firstIndex(where: { $0.id == projectId }) { self.projects[i].name = newName }
            }
        } catch { print("[ProjectsRepository] rename error: \(error)") }
    }

    func delete(userId: String, projectId: String) async {
        if FeatureFlags.disableProjectSaving { return }
        do {
            try await db.collection("users").document(userId).collection("projects").document(projectId).delete()
            await MainActor.run { self.projects.removeAll { $0.id == projectId } }
        } catch { print("[ProjectsRepository] delete error: \(error)") }
    }

    func attachVideo(userId: String, projectId: String, localURL: URL) async {
        if FeatureFlags.disableProjectSaving { return }
        let path = "users/\(userId)/projects/\(projectId)/video.mp4"
        let ref = storage.reference(withPath: path)
        do {
            _ = try await ref.putFileAsync(from: localURL)
            let url = try await ref.downloadURL()
            try await db.collection("users").document(userId).collection("projects").document(projectId).updateData(["videoURL": url.absoluteString])
            await MainActor.run { if let i = self.projects.firstIndex(where: { $0.id == projectId }) { self.projects[i].videoURL = url } }
        } catch { print("[ProjectsRepository] attachVideo error: \(error)") }
    }

    // Persist storyboard linkage so editor can continue with "+"
    func attachStoryboardContext(userId: String, projectId: String, storyboardId: String, currentSceneIndex: Int, totalScenes: Int) async {
        if FeatureFlags.disableProjectSaving { return }
        do {
            try await db.collection("users").document(userId).collection("projects").document(projectId).updateData([
                "storyboardId": storyboardId,
                "currentSceneIndex": currentSceneIndex,
                "totalScenes": totalScenes
            ])
            await MainActor.run {
                if let i = self.projects.firstIndex(where: { $0.id == projectId }) {
                    self.projects[i].storyboardId = storyboardId
                    self.projects[i].currentSceneIndex = currentSceneIndex
                    self.projects[i].totalScenes = totalScenes
                }
            }
        } catch {
            print("[ProjectsRepository] attachStoryboardContext error: \(error)")
        }
    }

    func uploadThumbnail(userId: String, projectId: String, image: UIImage) async {
        if FeatureFlags.disableProjectSaving { return }
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        let path = "users/\(userId)/projects/\(projectId)/thumb.jpg"
        let ref = storage.reference(withPath: path)
        do {
            _ = try await ref.putDataAsync(data)
            let url = try await ref.downloadURL()
            try await db.collection("users").document(userId).collection("projects").document(projectId).updateData(["thumbURL": url.absoluteString])
            await MainActor.run { if let i = self.projects.firstIndex(where: { $0.id == projectId }) { self.projects[i].thumbURL = url } }
        } catch { print("[ProjectsRepository] uploadThumbnail error: \(error)") }
    }
}


