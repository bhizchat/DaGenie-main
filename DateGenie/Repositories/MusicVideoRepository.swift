import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

/// Repository for the music video flow. This will later call Cloud Functions and Replicate.
@MainActor
final class MusicVideoRepository {
    static let shared = MusicVideoRepository()
    private init() {}

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    struct CreateProjectResult { let projectId: String; let audioGsPath: String; let referenceUrl: String }

    func createProjectAndUpload(userId: String, referenceImageData: Data, audioURL: URL) async throws -> CreateProjectResult {
        let projectId = UUID().uuidString
        let root = "users/\(userId)/musicVideos/\(projectId)"
        // Upload reference image
        let refRef = storage.reference(withPath: "\(root)/reference.jpg")
        _ = try await refRef.putDataAsync(referenceImageData, metadata: nil)
        let refUrl = try await refRef.downloadURL().absoluteString
        // Upload audio
        let audioRef = storage.reference(withPath: "\(root)/audio/track\(audioURL.pathExtension.isEmpty ? ".m4a" : ".\(audioURL.pathExtension)")")
        let data = try Self.loadAudioData(from: audioURL)
        _ = try await audioRef.putDataAsync(data, metadata: nil)
        let audioGs = "gs://\(storage.reference().bucket)/\(audioRef.fullPath)"
        // Seed firestore doc
        try await db.collection("users").document(userId).collection("musicVideos").document(projectId).setData([
            "status": "created",
            "createdAt": FieldValue.serverTimestamp(),
            "referenceImage": refUrl,
            "audio": ["gs": audioGs],
        ])
        return CreateProjectResult(projectId: projectId, audioGsPath: audioGs, referenceUrl: refUrl)
    }
}

// MARK: - Avatar generation client
extension MusicVideoRepository {
    struct AvatarResult: Decodable { let avatarUrl: String }

    func generateAvatar(referenceImageUrl: String, prompt: String? = nil) async throws -> String {
        let gcp = (Bundle.main.object(forInfoDictionaryKey: "FirebaseProjectID") as? String) ?? "dategenie-dev"
        let url = URL(string: "https://us-central1-\(gcp).cloudfunctions.net/generateFluxAvatar")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["referenceImage": referenceImageUrl]
        if let p = prompt { body["prompt"] = p }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "MusicVideoRepository", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "avatar_failed"])
        }
        let obj = try JSONDecoder().decode(AvatarResult.self, from: data)
        return obj.avatarUrl
    }

    /// Convenience: send a UIImage as a data URI so backend can rehost and process
    func generateAvatar(from image: UIImage, prompt: String? = nil) async throws -> String {
        guard let data = image.pngData() else { throw NSError(domain: "MusicVideoRepository", code: -2, userInfo: [NSLocalizedDescriptionKey: "image_encoding_failed"]) }
        let b64 = data.base64EncodedString()
        let dataUri = "data:image/png;base64,\(b64)"
        return try await generateAvatar(referenceImageUrl: dataUri, prompt: prompt)
    }

    // MARK: - Helpers
    private static func loadAudioData(from url: URL) throws -> Data {
        var accessed = false
        if url.startAccessingSecurityScopedResource() { accessed = true }
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            return try Data(contentsOf: url)
        }
        // Attempt to copy to a stable temp location (iCloud/file-provider edge cases)
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("picked_audio_\(UUID().uuidString).\(ext)")
        do {
            try fm.copyItem(at: url, to: tmp)
            return try Data(contentsOf: tmp)
        } catch {
            throw NSError(domain: "MusicVideoRepository", code: -3, userInfo: [NSLocalizedDescriptionKey: "audio_file_unavailable: \(url.path)"])
        }
    }
}

// MARK: - Finishing pipeline client calls
extension MusicVideoRepository {
    func startMusicFinishing(uid: String, projectId: String, storyboardId: String, runId: String, audioGsPath: String, audioDurationSec: Double) async throws {
        let gcp = (Bundle.main.object(forInfoDictionaryKey: "FirebaseProjectID") as? String) ?? "dategenie-dev"
        let url = URL(string: "https://us-central1-\(gcp).cloudfunctions.net/startMusicFinishing")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "uid": uid,
            "projectId": projectId,
            "storyboardId": storyboardId,
            "runId": runId,
            "audioGsPath": audioGsPath,
            "audioDurationSec": audioDurationSec
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "MusicVideoRepository", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "startMusicFinishing_failed"])
        }
    }

    func submitLipsync(uid: String, projectId: String, storyboardId: String, runId: String) async throws {
        let gcp = (Bundle.main.object(forInfoDictionaryKey: "FirebaseProjectID") as? String) ?? "dategenie-dev"
        let url = URL(string: "https://us-central1-\(gcp).cloudfunctions.net/submitLipsync")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["uid": uid, "projectId": projectId, "storyboardId": storyboardId, "runId": runId]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "MusicVideoRepository", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "submitLipsync_failed"])
        }
    }

    func muxAudioVideo(uid: String, projectId: String, storyboardId: String, runId: String) async throws {
        let gcp = (Bundle.main.object(forInfoDictionaryKey: "FirebaseProjectID") as? String) ?? "dategenie-dev"
        let url = URL(string: "https://us-central1-\(gcp).cloudfunctions.net/muxAudioVideo")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["uid": uid, "projectId": projectId, "storyboardId": storyboardId, "runId": runId]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "MusicVideoRepository", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "muxAudioVideo_failed"])
        }
    }
}


