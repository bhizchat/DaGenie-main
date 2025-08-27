import Foundation
import UIKit
import PencilKit
import AVFoundation
import CoreMedia
import QuartzCore

// Utility for merging a base image with PKDrawing and text overlays.
// Assumes overlay positions are expressed in canvas-local coordinates where
// the origin is the top-left of the canvas container used on screen.
enum OverlayExporter {
    // Render a merged UIImage in pixel space
    static func renderMergedImage(baseImage: UIImage,
                                  canvasRect: CGRect,
                                  drawing: PKDrawing,
                                  texts: [TextOverlay]) -> UIImage {
        let sizePx = CGSize(width: baseImage.size.width * baseImage.scale,
                            height: baseImage.size.height * baseImage.scale)

        // If canvas is not measured yet, fall back to full image bounds
        let safeCanvas: CGRect = (canvasRect.width > 0 && canvasRect.height > 0)
            ? canvasRect
            : CGRect(origin: .zero, size: CGSize(width: sizePx.width, height: sizePx.height))

        // Convert canvas points to output pixels
        let exportScale = sizePx.width / max(safeCanvas.width, 1)

        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        if #available(iOS 12.0, *) {
            fmt.preferredRange = .standard
        }

        let renderer = UIGraphicsImageRenderer(size: sizePx, format: fmt)
        let image = renderer.image { ctx in
            // Base
            baseImage.draw(in: CGRect(origin: .zero, size: sizePx))

            // Drawing
            let drawingImage = drawing.image(from: CGRect(origin: .zero, size: safeCanvas.size), scale: exportScale)
            drawingImage.draw(in: CGRect(x: 0,
                                         y: 0,
                                         width: safeCanvas.width * exportScale,
                                         height: safeCanvas.height * exportScale))

            // Texts (sorted for stable z-order)
            for t in texts.sorted(by: { $0.zIndex < $1.zIndex }) {
                draw(text: t, in: ctx.cgContext, exportScale: exportScale)
            }
        }
        return image
    }

    // Save merged UIImage to a temporary JPEG file
    static func exportMergedImage(baseImage: UIImage,
                                  canvasRect: CGRect,
                                  drawing: PKDrawing,
                                  texts: [TextOverlay]) -> URL? {
        let img = renderMergedImage(baseImage: baseImage,
                                    canvasRect: canvasRect,
                                    drawing: drawing,
                                    texts: texts)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dg_merged_\(UUID().uuidString).jpg")
        if let data = img.jpegData(compressionQuality: 0.95) {
            try? data.write(to: url)
            return url
        }
        return nil
    }

    // MARK: - Helpers
    private static func draw(text t: TextOverlay,
                              in cg: CGContext,
                              exportScale: CGFloat) {
        let font: UIFont = {
            switch t.style {
            case .small: return .systemFont(ofSize: 24, weight: .regular)
            case .largeCenter, .largeBackground: return .boldSystemFont(ofSize: 42)
            }
        }()
        let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.8); shadow.shadowOffset = .init(width: 0, height: 1); shadow.shadowBlurRadius = 3
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: t.color.uiColor,
            .shadow: shadow,
            .strokeColor: UIColor.black,
            .strokeWidth: -2.0
        ]
        let ns = NSString(string: t.string.isEmpty ? " " : t.string)
        let bounds = ns.size(withAttributes: attrs)
        cg.saveGState()
        // Canvas-local → pixel space (no canvas origin added)
        let tx = t.position.x * exportScale
        let ty = t.position.y * exportScale
        cg.translateBy(x: tx, y: ty)
        cg.rotate(by: t.rotation)
        // Scale into pixel space so exported text matches UI size
        cg.scaleBy(x: t.scale * exportScale, y: t.scale * exportScale)
        cg.translateBy(x: -bounds.width/2, y: -bounds.height/2)
        ns.draw(at: .zero, withAttributes: attrs)
        cg.restoreGState()
    }
}

// MARK: - Video Exporter
enum VideoOverlayExporter {
    static func export(assetURL: URL,
                        texts: [TextOverlay],
                        caption: CaptionModel,
                        canvasRect: CGRect,
                        completion: @escaping (URL?) -> Void) {
        let asset = AVAsset(url: assetURL)
        guard let track = asset.tracks(withMediaType: .video).first else { completion(nil); return }
        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { completion(nil); return }
        do {
            try compTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: track, at: .zero)
        } catch { completion(nil); return }

        // Include original audio tracks if present so the export retains sound
        let audioTracks = asset.tracks(withMediaType: .audio)
        for src in audioTracks {
            if let dst = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                do {
                    let timeRange = CMTimeRange(start: .zero, duration: min(src.timeRange.duration, asset.duration))
                    try dst.insertTimeRange(timeRange, of: src, at: .zero)
                } catch {
                    // Skip audio track on error, continue with others
                    continue
                }
            }
        }

        // Compute oriented source size
        let t = track.preferredTransform
        let sizeApplied = track.naturalSize.applying(t)
        let srcSize = CGSize(width: abs(sizeApplied.width), height: abs(sizeApplied.height))

        // Determine 4:5 target render size using center-crop logic (no letterboxing)
        let targetAR: CGFloat = 4.0/5.0
        let srcAR: CGFloat = srcSize.width / max(srcSize.height, 1)
        var renderSize: CGSize
        var cropDx: CGFloat = 0
        var cropDy: CGFloat = 0
        if srcAR < targetAR {
            // Source is taller/narrower than 4:5 → crop top/bottom, preserve width
            let outWidth = srcSize.width
            let outHeight = round(outWidth / targetAR)
            renderSize = CGSize(width: outWidth, height: outHeight)
            cropDy = round((srcSize.height - outHeight) / 2)
        } else if srcAR > targetAR {
            // Source is wider than 4:5 → crop sides, preserve height
            let outHeight = srcSize.height
            let outWidth = round(outHeight * targetAR)
            renderSize = CGSize(width: outWidth, height: outHeight)
            cropDx = round((srcSize.width - outWidth) / 2)
        } else {
            renderSize = srcSize
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        let fps: Int32 = Int32(round(track.nominalFrameRate).clamped(to: 1...60))
        videoComposition.frameDuration = CMTime(value: 1, timescale: fps)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)
        // Apply preferred orientation plus a translation to center-crop into 4:5
        var cropTransform = CGAffineTransform.identity
        if cropDx != 0 || cropDy != 0 { cropTransform = cropTransform.translatedBy(x: -cropDx, y: -cropDy) }
        let finalTransform = track.preferredTransform.concatenating(cropTransform)
        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // Core Animation overlay stack (in 4:5 render space)
        let parentLayer = CALayer(); parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer(); videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)

        let exportScale = renderSize.width / max(canvasRect.width, 1)

        // Text overlays
        for tOverlay in texts.sorted(by: { $0.zIndex < $1.zIndex }) {
            let layer = CATextLayer()
            let font = UIFont.systemFont(ofSize: 42, weight: .bold) // approximate; we use attributes below to size
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: tOverlay.color.uiColor
            ]
            let ns = NSString(string: tOverlay.string.isEmpty ? " " : tOverlay.string)
            let bounds = ns.size(withAttributes: attrs)
            layer.string = ns
            layer.alignmentMode = .center
            layer.foregroundColor = tOverlay.color.uiColor.cgColor
            layer.backgroundColor = UIColor.clear.cgColor
            layer.contentsScale = UIScreen.main.scale
            layer.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
            let px = tOverlay.position.x * exportScale
            let py = tOverlay.position.y * exportScale
            var transform = CATransform3DIdentity
            transform = CATransform3DTranslate(transform, px, py, 0)
            transform = CATransform3DRotate(transform, tOverlay.rotation, 0, 0, 1)
            transform = CATransform3DScale(transform, tOverlay.scale * exportScale, tOverlay.scale * exportScale, 1)
            // Center anchor
            layer.position = CGPoint(x: 0, y: 0)
            layer.transform = transform
            parentLayer.addSublayer(layer)
        }

        // Caption (optional, single line bar)
        if caption.isVisible && !caption.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let captionLayer = CATextLayer()
            captionLayer.contentsScale = UIScreen.main.scale
            captionLayer.alignmentMode = .center
            captionLayer.foregroundColor = caption.textColor.uiColor.cgColor
            let font = UIFont.systemFont(ofSize: caption.fontSize * exportScale, weight: .semibold)
            let attr = [NSAttributedString.Key.font: font,
                        NSAttributedString.Key.foregroundColor: caption.textColor.uiColor]
            let ns = NSString(string: caption.text)
            let width = renderSize.width - 64 * exportScale
            let rect = ns.boundingRect(with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attr, context: nil)
            captionLayer.string = caption.text
            captionLayer.bounds = CGRect(x: 0, y: 0, width: width, height: rect.height)
            let y = (canvasRect.minY + caption.verticalOffsetNormalized * canvasRect.height) * exportScale
            captionLayer.position = CGPoint(x: renderSize.width/2, y: y)
            parentLayer.addSublayer(captionLayer)
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dg_video_\(UUID().uuidString).mp4")
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { completion(nil); return }
        exporter.videoComposition = videoComposition
        exporter.outputURL = outURL
        exporter.outputFileType = .mp4
        exporter.exportAsynchronously {
            completion(exporter.status == .completed ? outURL : nil)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}


