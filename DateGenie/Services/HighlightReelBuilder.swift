import AVFoundation
import UIKit

enum HighlightReelError: Error {
    case noClips
    case noVideos
}

final class HighlightReelBuilder {
    static let shared = HighlightReelBuilder()
    private init() {}

    // Lightweight composer: concatenate provided local video URLs in order.
    // Use this overload in place of the legacy JourneyPersistence-backed variant.
    func buildReel(fromLocalVideoURLs localVideoURLs: [URL], completion: @escaping (Result<URL, Error>) -> Void) {
        guard !localVideoURLs.isEmpty else {
            completion(.failure(HighlightReelError.noVideos)); return
        }
        self.exportLocalVideos(from: localVideoURLs, completion: completion)
    }

    // Legacy signature retained for source compatibility; no longer fetches from persistence.
    // Call the URL-based overload instead.
    func buildReel(level: Int, runId: String, completion: @escaping (Result<URL, Error>) -> Void) {
        print("[HighlightReelBuilder] buildReel(level:runId:) deprecated; supply local video URLs explicitly.")
        completion(.failure(HighlightReelError.noClips))
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


