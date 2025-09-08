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
        do {
            let snap = try await db.collection("users").document(userId).collection("projects").order(by: "createdAt", descending: true).getDocuments()
            let results: [Project] = snap.documents.compactMap { doc in
                let data = doc.data()
                let id = doc.documentID
                let name = data["name"] as? String ?? "Untitled"
                let ts = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                let vidStr = data["videoURL"] as? String
                let thStr = data["thumbURL"] as? String
                return Project(id: id, name: name, createdAt: ts, videoURL: vidStr.flatMap(URL.init), thumbURL: thStr.flatMap(URL.init))
            }
            await MainActor.run { self.projects = results }
        } catch {
            print("[ProjectsRepository] load error: \(error)")
        }
    }

    func create(userId: String, name: String = "New Video") async -> Project? {
        let id = UUID().uuidString
        let doc = db.collection("users").document(userId).collection("projects").document(id)
        let now = Date()
        let model = Project(id: id, name: name, createdAt: now, videoURL: nil, thumbURL: nil)
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

    func rename(userId: String, projectId: String, to newName: String) async {
        do { try await db.collection("users").document(userId).collection("projects").document(projectId).updateData(["name": newName])
            await MainActor.run {
                if let i = self.projects.firstIndex(where: { $0.id == projectId }) { self.projects[i].name = newName }
            }
        } catch { print("[ProjectsRepository] rename error: \(error)") }
    }

    func delete(userId: String, projectId: String) async {
        do {
            try await db.collection("users").document(userId).collection("projects").document(projectId).delete()
            await MainActor.run { self.projects.removeAll { $0.id == projectId } }
        } catch { print("[ProjectsRepository] delete error: \(error)") }
    }

    func attachVideo(userId: String, projectId: String, localURL: URL) async {
        let path = "users/\(userId)/projects/\(projectId)/video.mp4"
        let ref = storage.reference(withPath: path)
        do {
            _ = try await ref.putFileAsync(from: localURL)
            let url = try await ref.downloadURL()
            try await db.collection("users").document(userId).collection("projects").document(projectId).updateData(["videoURL": url.absoluteString])
            await MainActor.run { if let i = self.projects.firstIndex(where: { $0.id == projectId }) { self.projects[i].videoURL = url } }
        } catch { print("[ProjectsRepository] attachVideo error: \(error)") }
    }

    func uploadThumbnail(userId: String, projectId: String, image: UIImage) async {
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


