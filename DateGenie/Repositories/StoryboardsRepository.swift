import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Repository for persisting and querying storyboard sets and scenes.
///
/// This talks to Cloud Functions endpoints:
/// - saveStoryboardSet (HTTP)
/// - enqueueSceneVideo (HTTP)
@MainActor
final class StoryboardsRepository {
    static let shared = StoryboardsRepository()
    private init() {}

    private let db: Firestore = Firestore.firestore()

    private func functionsBaseURL(projectId: String) -> String {
        // Keep region consistent with backend (us-central1)
        return "https://us-central1-\(projectId).cloudfunctions.net"
    }

    // MARK: - Save storyboard set

    struct SaveStoryboardResponse: Decodable { let storyboardId: String }

    /// Persists a storyboard plan (with images already attached) and links it to the project.
    /// - Parameters:
    ///   - userId: Firebase auth UID
    ///   - projectId: The project this storyboard belongs to
    ///   - plan: The completed plan (including scenes with imageUrl)
    ///   - requestId: Optional correlation id for logs
    ///   - idempotencyKey: Optional idempotency key to guard client retries
    ///   - bumpVersion: Whether to read/flip `isLatest` and bump version server-side
    func saveStoryboardSet(userId: String,
                           projectId: String,
                           plan: StoryboardPlan,
                           requestId: String? = nil,
                           idempotencyKey: String? = nil,
                           bumpVersion: Bool = true,
                           gcpProjectId: String = (Bundle.main.object(forInfoDictionaryKey: "FirebaseProjectID") as? String) ?? "dategenie-dev") async throws -> String {
        let urlStr = functionsBaseURL(projectId: gcpProjectId) + "/saveStoryboardSet"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "uid": userId,
            "projectId": projectId,
            "characterId": plan.character.id,
            "settings": [
                "aspectRatio": plan.settings.aspectRatio,
                "style": plan.settings.style,
                "camera": plan.settings.camera as Any
            ],
            "referenceImageUrls": plan.referenceImageUrls ?? [],
            "providerDefault": NSNull(),
            "scenes": plan.scenes.map { s in
                return [
                    "index": s.index,
                    "prompt": s.prompt,
                    "script": s.script,
                    "action": s.action as Any,
                    "animation": s.animation as Any,
                    "speechType": s.speechType as Any,
                    "speech": s.speech as Any,
                    "durationSec": s.durationSec as Any,
                    "wordsPerSec": s.wordsPerSec as Any,
                    "wordBudget": s.wordBudget as Any,
                    "imageUrl": s.imageUrl as Any
                ]
            },
            "bumpVersion": bumpVersion
        ]
        if let key = idempotencyKey { body["idempotencyKey"] = key }
        if let rid = requestId { body["requestId"] = rid }

        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "StoryboardsRepository", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "saveStoryboardSet failed"])
        }
        let decoded = try JSONDecoder().decode(SaveStoryboardResponse.self, from: data)
        return decoded.storyboardId
    }

    // MARK: - Enqueue generation for a scene

    struct EnqueueResponse: Decodable { let ok: Bool; let taskName: String? }

    func enqueueSceneVideo(userId: String,
                           projectId: String,
                           storyboardId: String,
                           sceneId: String,
                           provider: String? = nil,
                           requestId: String? = nil,
                           delaySeconds: Int? = nil,
                           nameSuffix: String? = nil,
                           gcpProjectId: String = (Bundle.main.object(forInfoDictionaryKey: "FirebaseProjectID") as? String) ?? "dategenie-dev") async throws {
        let urlStr = functionsBaseURL(projectId: gcpProjectId) + "/enqueueSceneVideo"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "uid": userId,
            "projectId": projectId,
            "storyboardId": storyboardId,
            "sceneId": sceneId
        ]
        if let p = provider { body["provider"] = p }
        if let rid = requestId { body["requestId"] = rid }
        if let d = delaySeconds { body["delaySeconds"] = d }
        if let sfx = nameSuffix { body["nameSuffix"] = sfx }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "StoryboardsRepository", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "enqueueSceneVideo failed"])
        }
        _ = try? JSONDecoder().decode(EnqueueResponse.self, from: data)
    }
}


