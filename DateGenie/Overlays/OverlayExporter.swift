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
    /// Backward-compatible export.
    static func export(assetURL: URL,
                        texts: [TextOverlay],
                        caption: CaptionModel,
                        canvasRect: CGRect,
                        logo: UIImage? = nil,
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

        // Optional brand logo fade-in at the bottom-center for the last 3 seconds
        if let logo = logo?.cgImage {
            let logoLayer = CALayer()
            let maxWidth = renderSize.width * 0.35
            let aspect = CGFloat(logo.width) / CGFloat(max(logo.height, 1))
            let width = min(maxWidth, CGFloat(logo.width))
            let height = width / max(aspect, 0.001)
            logoLayer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            logoLayer.contents = logo
            logoLayer.contentsScale = UIScreen.main.scale
            // Bottom-center placement, slightly above the bottom edge
            let bottomY = renderSize.height - height/2 - (renderSize.height * 0.06)
            logoLayer.position = CGPoint(x: renderSize.width/2, y: bottomY)
            logoLayer.opacity = 0.0

            // Fade-in animation during the last 3 seconds of the video
            let threeSeconds = min(CMTimeGetSeconds(asset.duration), 3.0)
            let total = CMTimeGetSeconds(asset.duration)
            let start = max(total - threeSeconds, 0)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.0
            fade.toValue = 1.0
            fade.beginTime = CFTimeInterval(start)
            fade.duration = CFTimeInterval(threeSeconds)
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            logoLayer.add(fade, forKey: "fadeIn")
            parentLayer.addSublayer(logoLayer)
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

    /// New overload supporting aspect ratio and timed items.
    static func export(assetURL: URL,
                        timedTexts: [TimedTextOverlay],
                        timedCaptions: [TimedCaption],
                        renderConfig: VideoRenderConfig,
                        audioTracks: [AudioTrack],
                        originalClipVolume: Float? = nil,
                        canvasRect: CGRect,
                        completion: @escaping (URL?) -> Void) {
        let asset = AVAsset(url: assetURL)
        guard let track = asset.tracks(withMediaType: .video).first else { completion(nil); return }
        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { completion(nil); return }
        do {
            try compTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: track, at: .zero)
        } catch { completion(nil); return }

        // Include original audio tracks and collect mix params when a level is provided
        var mixParams: [AVMutableAudioMixInputParameters] = []
        for src in asset.tracks(withMediaType: .audio) {
            if let dst = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                do {
                    try dst.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: src, at: .zero)
                    if let vol = originalClipVolume {
                        let p = AVMutableAudioMixInputParameters(track: dst)
                        p.setVolume(vol, at: .zero)
                        mixParams.append(p)
                    }
                } catch { /* ignore */ }
            }
        }

        // Add extra audio tracks
        for t in audioTracks {
            let aAsset = AVURLAsset(url: t.url)
            if let aSrc = aAsset.tracks(withMediaType: .audio).first,
               let aDst = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                do {
                    let maxDur = max(.zero, asset.duration - t.start)
                    let dur = min(aAsset.duration, t.duration, maxDur)
                    try aDst.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: aSrc, at: t.start)
                    let p = AVMutableAudioMixInputParameters(track: aDst)
                    p.setVolume(t.volume, at: .zero)
                    mixParams.append(p)
                } catch { /* ignore */ }
            }
        }

        // Render size and transform
        let oriented = track.naturalSize.applying(track.preferredTransform)
        let srcSize = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let size = renderConfig.renderSize(for: srcSize)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = size
        let fps: Int32 = Int32(round(track.nominalFrameRate).clamped(to: 1...60))
        videoComposition.frameDuration = CMTime(value: 1, timescale: fps)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)
        layerInstruction.setTransform(renderConfig.transformForCrop(track: track, renderSize: size), at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // Overlay layers
        let parentLayer = CALayer(); parentLayer.frame = CGRect(origin: .zero, size: size)
        let videoLayer = CALayer(); videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)

        // Scale from canvas points to render pixels for overlay math
        let exportScale = size.width / max(canvasRect.width, 1)

        func addTimedOpacityAnimations(layer: CALayer, start: CMTime, duration: CMTime) {
            let begin = CMTimeGetSeconds(start)
            let end = CMTimeGetSeconds(start + duration)
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0.0
            fadeIn.toValue = 1.0
            fadeIn.beginTime = begin
            fadeIn.duration = 0.1
            fadeIn.fillMode = .forwards
            fadeIn.isRemovedOnCompletion = false
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1.0
            fadeOut.toValue = 0.0
            fadeOut.beginTime = end
            fadeOut.duration = 0.1
            fadeOut.fillMode = .forwards
            fadeOut.isRemovedOnCompletion = false
            layer.add(fadeIn, forKey: "fadeIn")
            layer.add(fadeOut, forKey: "fadeOut")
        }

        for tOverlay in timedTexts.sorted(by: { $0.base.zIndex < $1.base.zIndex }) {
            let base = tOverlay.base
            let font = UIFont.boldSystemFont(ofSize: 42)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: base.color.uiColor]
            let ns = NSString(string: base.string.isEmpty ? " " : base.string)
            let bounds = ns.size(withAttributes: attrs)

            let textLayer = CATextLayer()
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.alignmentMode = .center
            textLayer.foregroundColor = base.color.uiColor.cgColor
            textLayer.backgroundColor = UIColor.clear.cgColor
            textLayer.string = ns
            textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)

            let px = base.position.x * exportScale
            let py = base.position.y * exportScale
            var transform = CATransform3DIdentity
            transform = CATransform3DTranslate(transform, px, py, 0)
            transform = CATransform3DRotate(transform, base.rotation, 0, 0, 1)
            transform = CATransform3DScale(transform, base.scale * exportScale, base.scale * exportScale, 1)
            textLayer.position = CGPoint(x: 0, y: 0)
            textLayer.transform = transform

            addTimedOpacityAnimations(layer: textLayer, start: tOverlay.start, duration: tOverlay.duration)
            parentLayer.addSublayer(textLayer)
        }

        for cap in timedCaptions {
            guard cap.base.isVisible else { continue }
            let text = cap.base.text
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let captionLayer = CATextLayer()
            captionLayer.contentsScale = UIScreen.main.scale
            captionLayer.alignmentMode = .center
            captionLayer.foregroundColor = cap.base.textColor.uiColor.cgColor
            let font = UIFont.systemFont(ofSize: cap.base.fontSize * exportScale, weight: .semibold)
            let attr = [NSAttributedString.Key.font: font,
                        NSAttributedString.Key.foregroundColor: cap.base.textColor.uiColor]
            let ns = NSString(string: text)
            let width = size.width - 64 * exportScale
            let rect = ns.boundingRect(with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attr, context: nil)
            captionLayer.string = text
            captionLayer.bounds = CGRect(x: 0, y: 0, width: width, height: rect.height)
            let y = (canvasRect.minY + cap.base.verticalOffsetNormalized * canvasRect.height) * exportScale
            captionLayer.position = CGPoint(x: size.width/2, y: y)
            addTimedOpacityAnimations(layer: captionLayer, start: cap.start, duration: cap.duration)
            parentLayer.addSublayer(captionLayer)
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dg_video_\(UUID().uuidString).mp4")
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { completion(nil); return }
        exporter.videoComposition = videoComposition
        if !mixParams.isEmpty { let mix = AVMutableAudioMix(); mix.inputParameters = mixParams; exporter.audioMix = mix }
        exporter.outputURL = outURL
        exporter.outputFileType = .mp4
        exporter.exportAsynchronously { completion(exporter.status == .completed ? outURL : nil) }
    }

    /// Export from an already-built AVAsset (e.g., an AVMutableComposition that already encodes
    /// timeline edits like speed changes). Overlays are composited in the asset's render size.
    static func export(from baseAsset: AVAsset,
                       audioMix: AVAudioMix? = nil,
                       timedTexts: [TimedTextOverlay],
                       timedCaptions: [TimedCaption],
                       timedMedia: [TimedMediaOverlay] = [],
                       canvasRect: CGRect,
                       completion: @escaping (URL?) -> Void) {
        // Build a fresh composition so we can add overlay video tracks with transforms
        let composition = AVMutableComposition()
        // Base video track
        var size = CGSize(width: 1080, height: 1920)
        if let baseSrc = baseAsset.tracks(withMediaType: .video).first,
           let baseDst = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            do {
                try baseDst.insertTimeRange(CMTimeRange(start: .zero, duration: baseAsset.duration), of: baseSrc, at: .zero)
                let oriented = baseSrc.naturalSize.applying(baseSrc.preferredTransform)
                size = CGSize(width: abs(oriented.width), height: abs(oriented.height))
            } catch { /* ignore */ }
        }

        // Video composition with layer instructions (base + overlay videos)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = size
        let fpsTrack = baseAsset.tracks(withMediaType: .video).first
        let fps: Int32 = Int32(round(fpsTrack?.nominalFrameRate ?? 30).clamped(to: 1...60))
        videoComposition.frameDuration = CMTime(value: 1, timescale: fps)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []

        if let baseDst = composition.tracks(withMediaType: .video).first {
            let baseLI = AVMutableVideoCompositionLayerInstruction(assetTrack: baseDst)
            // Apply the base orientation transform if available
            if let baseSrc = baseAsset.tracks(withMediaType: .video).first {
                baseLI.setTransform(baseSrc.preferredTransform, at: .zero)
            }
            layerInstructions.append(baseLI)
        }

        // Add overlay video tracks
        let exportScale = size.width / max(canvasRect.width, 1)
        for m in timedMedia where m.kind == .video {
            let a = AVURLAsset(url: m.url)
            guard let src = a.tracks(withMediaType: .video).first,
                  let dst = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let srcRange = CMTimeRange(start: m.trimStart, duration: m.trimmedDuration)
            do {
                try dst.insertTimeRange(srcRange, of: src, at: m.effectiveStart)
                let li = AVMutableVideoCompositionLayerInstruction(assetTrack: dst)
                // Build PIP transform from canvas-space params
                let nat = src.naturalSize.applying(src.preferredTransform)
                let ow = max(1.0, abs(nat.width))
                let oh = max(1.0, abs(nat.height))
                let sx = m.scale * exportScale
                let sy = m.scale * exportScale
                let tx = m.position.x * exportScale - (ow * sx) / 2
                let ty = m.position.y * exportScale - (oh * sy) / 2
                var t = src.preferredTransform
                t = t.concatenating(CGAffineTransform(scaleX: sx, y: sy))
                if m.rotation != 0 { t = t.concatenating(CGAffineTransform(rotationAngle: m.rotation)) }
                t = t.concatenating(CGAffineTransform(translationX: tx, y: ty))
                li.setTransform(t, at: m.effectiveStart)
                layerInstructions.append(li)
            } catch { /* ignore */ }
        }

        instruction.layerInstructions = layerInstructions
        videoComposition.instructions = [instruction]

        // Overlay layers sized to the asset's render size
        let parentLayer = CALayer(); parentLayer.frame = CGRect(origin: .zero, size: size)
        let videoLayer = CALayer(); videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)

        // exportScale already declared above; do not redeclare

        func addTimedOpacityAnimations(layer: CALayer, start: CMTime, duration: CMTime) {
            let begin = CMTimeGetSeconds(start)
            let end = CMTimeGetSeconds(start + duration)
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0.0
            fadeIn.toValue = 1.0
            fadeIn.beginTime = begin
            fadeIn.duration = 0.1
            fadeIn.fillMode = .forwards
            fadeIn.isRemovedOnCompletion = false
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1.0
            fadeOut.toValue = 0.0
            fadeOut.beginTime = end
            fadeOut.duration = 0.1
            fadeOut.fillMode = .forwards
            fadeOut.isRemovedOnCompletion = false
            layer.add(fadeIn, forKey: "fadeIn")
            layer.add(fadeOut, forKey: "fadeOut")
        }

        for tOverlay in timedTexts.sorted(by: { $0.base.zIndex < $1.base.zIndex }) {
            let base = tOverlay.base
            let font = UIFont.boldSystemFont(ofSize: 42)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: base.color.uiColor]
            let ns = NSString(string: base.string.isEmpty ? " " : base.string)
            let bounds = ns.size(withAttributes: attrs)

            let textLayer = CATextLayer()
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.alignmentMode = .center
            textLayer.foregroundColor = base.color.uiColor.cgColor
            textLayer.backgroundColor = UIColor.clear.cgColor
            textLayer.string = ns
            textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)

            let px = base.position.x * exportScale
            let py = base.position.y * exportScale
            var transform = CATransform3DIdentity
            transform = CATransform3DTranslate(transform, px, py, 0)
            transform = CATransform3DRotate(transform, base.rotation, 0, 0, 1)
            transform = CATransform3DScale(transform, base.scale * exportScale, base.scale * exportScale, 1)
            textLayer.position = CGPoint(x: 0, y: 0)
            textLayer.transform = transform

            addTimedOpacityAnimations(layer: textLayer, start: tOverlay.start, duration: tOverlay.duration)
            parentLayer.addSublayer(textLayer)
        }

        for cap in timedCaptions {
        // Photo media overlays via CALayer
        for m in timedMedia where m.kind == .photo {
            if let img = UIImage(contentsOfFile: m.url.path)?.cgImage {
                let layer = CALayer()
                layer.contents = img
                layer.contentsScale = UIScreen.main.scale
                let px = m.position.x * exportScale
                let py = m.position.y * exportScale
                var transform = CATransform3DIdentity
                transform = CATransform3DTranslate(transform, px, py, 0)
                transform = CATransform3DRotate(transform, m.rotation, 0, 0, 1)
                transform = CATransform3DScale(transform, m.scale * exportScale, m.scale * exportScale, 1)
                layer.position = CGPoint(x: 0, y: 0)
                layer.transform = transform
                addTimedOpacityAnimations(layer: layer, start: m.start + m.trimStart, duration: m.trimmedDuration)
                parentLayer.addSublayer(layer)
            }
        }
            guard cap.base.isVisible else { continue }
            let text = cap.base.text
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let captionLayer = CATextLayer()
            captionLayer.contentsScale = UIScreen.main.scale
            captionLayer.alignmentMode = .center
            captionLayer.foregroundColor = cap.base.textColor.uiColor.cgColor
            let font = UIFont.systemFont(ofSize: cap.base.fontSize * exportScale, weight: .semibold)
            let attr = [NSAttributedString.Key.font: font,
                        NSAttributedString.Key.foregroundColor: cap.base.textColor.uiColor]
            let ns = NSString(string: text)
            let width = size.width - 64 * exportScale
            let rect = ns.boundingRect(with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attr, context: nil)
            captionLayer.string = text
            captionLayer.bounds = CGRect(x: 0, y: 0, width: width, height: rect.height)
            let y = (canvasRect.minY + cap.base.verticalOffsetNormalized * canvasRect.height) * exportScale
            captionLayer.position = CGPoint(x: size.width/2, y: y)
            addTimedOpacityAnimations(layer: captionLayer, start: cap.start, duration: cap.duration)
            parentLayer.addSublayer(captionLayer)
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dg_video_\(UUID().uuidString).mp4")
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { completion(nil); return }
        exporter.videoComposition = videoComposition
        if let mix = audioMix { exporter.audioMix = mix }
        exporter.outputURL = outURL
        exporter.outputFileType = .mp4
        exporter.exportAsynchronously { completion(exporter.status == .completed ? outURL : nil) }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}


