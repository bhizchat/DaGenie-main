import Foundation
import AVFoundation
import UIKit

enum ThumbnailGenerator {
    static func firstFrame(for url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        if let cg = try? gen.copyCGImage(at: time, actualTime: nil) {
            return UIImage(cgImage: cg)
        }
        return nil
    }

    // For remote assets that may not support efficient random access over HTTP,
    // download to a temporary file first and then extract the first frame.
    static func firstFrameFromRemote(url: URL) async -> UIImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tn_\(UUID().uuidString).mp4")
            try data.write(to: tmp)
            return firstFrame(for: tmp)
        } catch {
            return nil
        }
    }
}


