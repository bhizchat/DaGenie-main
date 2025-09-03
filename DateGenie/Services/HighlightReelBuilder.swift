import AVFoundation
import UIKit

enum HighlightReelError: Error {
    case noClips
    case noVideos
}

final class HighlightReelBuilder {
    static let shared = HighlightReelBuilder()
    private init() {}

    // Very lightweight MVP: concatenates media in order (videos only for reliability);
    // Downloads remote videos to local temp files before composition.
    func buildReel(level: Int, runId: String, completion: @escaping (Result<URL, Error>) -> Void) {
        JourneyPersistence.shared.loadAllMediaForRun(level: level, runId: runId) { items in
            let medias: [CapturedMedia] = items.map { item in
                CapturedMedia(localURL: item.remoteURL, type: item.type, caption: nil, remoteURL: item.remoteURL, uploadProgress: 1.0)
            }
            guard !medias.isEmpty else {
                print("[HighlightReelBuilder] no media found for run; aborting")
                completion(.failure(HighlightReelError.noClips)); return
            }
            let videos = medias.filter { $0.type == .video }
            guard !videos.isEmpty else {
                print("[HighlightReelBuilder] photos-only not supported in MVP; require >=1 video")
                completion(.failure(HighlightReelError.noVideos)); return
            }
            // Download to local temp files first to avoid AVURLAsset HTTP duration quirks
            let group = DispatchGroup()
            var localVideoURLs: [URL] = []
            let fm = FileManager.default
            for (idx, clip) in videos.enumerated() {
                guard let remote = clip.remoteURL else { continue }
                group.enter()
                let task = URLSession.shared.downloadTask(with: remote) { tempURL, _, err in
                    defer { group.leave() }
                    if let err = err { print("[HighlightReelBuilder] download error idx=\(idx): \(err)"); return }
                    guard let t = tempURL else { print("[HighlightReelBuilder] download returned nil tempURL idx=\(idx)"); return }
                    let dst = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dg_clip_\(UUID().uuidString).mp4")
                    do {
                        if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
                        try fm.copyItem(at: t, to: dst)
                        localVideoURLs.append(dst)
                    } catch { print("[HighlightReelBuilder] copy temp -> dst failed: \(error)") }
                }
                task.resume()
            }
            group.notify(queue: .main) {
                guard !localVideoURLs.isEmpty else {
                    print("[HighlightReelBuilder] no local videos downloaded; aborting")
                    completion(.failure(HighlightReelError.noVideos)); return
                }
                self.exportLocalVideos(from: localVideoURLs, completion: completion)
            }
        }
    }

    private func exportLocalVideos(from localURLs: [URL], completion: @escaping (Result<URL, Error>) -> Void) {
        // Bridge to async implementation to use modern AVFoundation loaders
        Task { await self.exportLocalVideosAsync(from: localURLs, completion: completion) }
    }

    private func exportLocalVideosAsync(from localURLs: [URL], completion: @escaping (Result<URL, Error>) -> Void) async {
        let mix = AVMutableComposition()
        let videoTrack = mix.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = mix.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        // Pick portrait target to match phone capture; adjust as needed
        let renderSize = CGSize(width: 1080, height: 1920)

        var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []

        func insertAsset(url: URL) async {
            let asset = AVURLAsset(url: url)
            guard let v = try? await asset.loadTracks(withMediaType: .video).first else { return }
            let a = try? await asset.loadTracks(withMediaType: .audio).first
            guard let duration = try? await asset.load(.duration) else { return }
            do {
                try videoTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: v, at: cursor)
                if let a = a { try audioTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: a, at: cursor) }

                // Build layer instruction honoring orientation and aspect-fit into renderSize
                let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack!)
                let naturalSize = (try? await v.load(.naturalSize)) ?? .zero
                let prefT = (try? await v.load(.preferredTransform)) ?? .identity
                let natural = naturalSize.applying(prefT)
                let clipSize = CGSize(width: abs(natural.width), height: abs(natural.height))
                let scale = min(renderSize.width / clipSize.width, renderSize.height / clipSize.height)
                let scaledSize = CGSize(width: clipSize.width * scale, height: clipSize.height * scale)
                let tx = (renderSize.width - scaledSize.width) / 2
                let ty = (renderSize.height - scaledSize.height) / 2

                var t = prefT
                t = t.concatenating(CGAffineTransform(scaleX: scale, y: scale))
                t = t.concatenating(CGAffineTransform(translationX: tx, y: ty))
                instruction.setTransform(t, at: cursor)
                // Apply static clip opacity (defaults to opaque). Wire keyframes later if needed.
                instruction.setOpacity(1.0, at: cursor)
                layerInstructions.append(instruction)

                cursor = cursor + duration
            } catch {
                print("[HighlightReelBuilder] composition insert error: \(error)")
            }
        }

        func insertPhoto(url: URL) {
            // Represent photo as a 2s silent clip by using a generator image overlay later
            // For MVP: just create a 2s black clip placeholder
            let twoSec = CMTime(seconds: 2, preferredTimescale: 600)
            cursor = CMTimeAdd(cursor, twoSec)
        }

        for url in localURLs { await insertAsset(url: url) }

        let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dg_reel_\(UUID().uuidString).mp4")
        if FileManager.default.fileExists(atPath: outURL.path) { try? FileManager.default.removeItem(at: outURL) }

        // Build video composition for orientation + scaling
        let mainInstruction = AVMutableVideoCompositionInstruction()
        mainInstruction.timeRange = CMTimeRange(start: .zero, duration: cursor)
        mainInstruction.layerInstructions = layerInstructions

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [mainInstruction]
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let exporter = AVAssetExportSession(asset: mix, presetName: AVAssetExportPresetHighestQuality)
        exporter?.outputURL = outURL
        exporter?.outputFileType = .mp4
        exporter?.videoComposition = videoComposition
        exporter?.exportAsynchronously {
            DispatchQueue.main.async {
                if exporter?.status == .completed { completion(.success(outURL)) }
                else { completion(.failure(exporter?.error ?? HighlightReelError.noClips)) }
            }
        }
    }
}


