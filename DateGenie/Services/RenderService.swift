import Foundation
import UIKit

struct RenderResult: Codable {
    var scenes: [RenderedScene]
}

struct RenderedScene: Codable { let index: Int; let imageUrl: String }

@MainActor
final class RenderService {
    static let shared = RenderService()
    private init() {}

    func render(plan: StoryboardPlan) async throws -> StoryboardPlan {
        Log.info("Render.start", ["sceneCount": plan.scenes.count])
        var copy = plan
        // Try remote generation first
        let base = "https://us-central1-\(VoiceAssistantVM.projectId()).cloudfunctions.net"
        if let url = URL(string: "\(base)/generateStoryboardImages") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            // Increase client-side timeout to accommodate long image generation
            req.timeoutInterval = 300
            // Only send one pending scene at a time for fast, reliable updates
            let pending = copy.scenes.filter { ($0.imageUrl ?? "").isEmpty }
            let batch = Array(pending.prefix(1))
            let payloadScenes = batch.map { s in
                return [
                    "index": s.index,
                    "prompt": s.prompt,
                    "action": s.action ?? "",
                    "speechType": s.speechType ?? "",
                    "speech": s.speech ?? "",
                    "animation": s.animation ?? ""
                ] as [String: Any]
            }
            var body: [String: Any] = [
                "scenes": payloadScenes,
                "style": copy.settings.style,
                "referenceImageUrls": copy.referenceImageUrls ?? [],
                "character": copy.character.id,
                "provider": "nano"
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
            Log.info("Render.remote.start", ["url": url.absoluteString])
            do {
                // Use a session with extended timeouts
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 300
                config.timeoutIntervalForResource = 300
                let session = URLSession(configuration: config)
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else {
                    Log.error("Render.remote.no_response", [:])
                    throw NSError(domain: "RenderService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
                }
                Log.info("Render.remote.response", ["status": http.statusCode])
                guard (200..<300).contains(http.statusCode) else {
                    let bodyText = String(data: data, encoding: .utf8) ?? ""
                    let snippet = String(bodyText.prefix(300))
                    Log.error("Render.remote.http_error", ["status": http.statusCode, "body": snippet])
                    throw NSError(domain: "RenderService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(snippet)"])
                }
                // Strong decode to avoid NSNumber/Double casting traps
                let result = try JSONDecoder().decode(RenderResult.self, from: data)
                let map = Dictionary(uniqueKeysWithValues: result.scenes.map { ($0.index, $0.imageUrl) })
                if map.isEmpty {
                    Log.warn("Render.remote.no_images", [:])
                    throw NSError(domain: "RenderService", code: -4, userInfo: [NSLocalizedDescriptionKey: "No images generated"])
                }
                for i in copy.scenes.indices {
                    let idx = copy.scenes[i].index
                    if let u = map[idx] { copy.scenes[i].imageUrl = u }
                }
                Log.info("Render.remote.done", ["attached": map.count])
                return copy
            } catch {
                Log.warn("Render.remote.fail", ["error": String(describing: error)])
            }
        }

        // Fallback: local placeholder tiles
        for i in copy.scenes.indices {
            let idx = copy.scenes[i].index
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("storyboard_render", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent("scene_\(idx).png")
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                let size = CGSize(width: 1024, height: 1024)
                UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
                UIColor(red: 0.97, green: 0.71, blue: 0.32, alpha: 1).setFill()
                UIRectFill(CGRect(origin: .zero, size: size))
                let text = "Scene \(idx)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 72, weight: .bold),
                    .foregroundColor: UIColor.darkGray
                ]
                let textSize = (text as NSString).size(withAttributes: attrs)
                (text as NSString).draw(at: CGPoint(x: (size.width - textSize.width)/2, y: (size.height - textSize.height)/2), withAttributes: attrs)
                let img = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                if let data = img?.pngData() { try? data.write(to: fileURL) }
            }
            copy.scenes[i].imageUrl = fileURL.absoluteString
            Log.info("Render.scene", ["index": idx, "url": fileURL.lastPathComponent])
        }
        Log.info("Render.done")
        return copy
    }

    // Render a single scene via the same endpoint to avoid long timeouts
    func renderOne(scene: PlanScene, plan: StoryboardPlan) async throws -> String? {
        guard let url = URL(string: "https://us-central1-dategenie-dev.cloudfunctions.net/generateStoryboardImages") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 300
        let payload: [String: Any] = [
            "scenes": [[
                "index": scene.index,
                "prompt": scene.prompt,
                "action": scene.action ?? "",
                "speechType": scene.speechType ?? "",
                "speech": scene.speech ?? "",
                "animation": scene.animation ?? ""
            ]],
            "style": plan.settings.style,
            "referenceImageUrls": plan.referenceImageUrls ?? [],
            "character": plan.character.id
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arr = json["scenes"] as? [[String: Any]], let first = arr.first,
           let u = first["imageUrl"] as? String {
            return u
        }
        return nil
    }
}


