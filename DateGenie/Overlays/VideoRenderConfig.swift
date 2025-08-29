import CoreGraphics
import AVFoundation

enum AspectRatio {
    case nineBySixteen
    case fourByFive
    case oneByOne

    var value: CGFloat {
        switch self {
        case .nineBySixteen: return 9.0/16.0
        case .fourByFive: return 4.0/5.0
        case .oneByOne: return 1.0
        }
    }
}

enum ContentMode {
    case cropCenter
    case letterbox
}

struct VideoRenderConfig {
    var aspect: AspectRatio
    var mode: ContentMode

    init(aspect: AspectRatio = .fourByFive, mode: ContentMode = .cropCenter) {
        self.aspect = aspect
        self.mode = mode
    }

    func renderSize(for sourceSize: CGSize) -> CGSize {
        switch mode {
        case .cropCenter:
            return cropCenterRenderSize(for: sourceSize)
        case .letterbox:
            // For letterbox we keep the same size; caller should add bars as needed
            return sourceSize
        }
    }

    private func cropCenterRenderSize(for sourceSize: CGSize) -> CGSize {
        let targetAR = aspect.value
        let srcAR = sourceSize.width / max(sourceSize.height, 1)
        if abs(srcAR - targetAR) < 0.0001 { return sourceSize }
        if srcAR < targetAR {
            // Taller than target: crop top/bottom
            let outWidth = sourceSize.width
            let outHeight = round(outWidth / targetAR)
            return CGSize(width: outWidth, height: outHeight)
        } else {
            // Wider than target: crop sides
            let outHeight = sourceSize.height
            let outWidth = round(outHeight * targetAR)
            return CGSize(width: outWidth, height: outHeight)
        }
    }

    func transformForCrop(track: AVAssetTrack, renderSize: CGSize) -> CGAffineTransform {
        // Apply preferred transform first, then translate to center-crop
        let t = track.preferredTransform
        let sizeApplied = track.naturalSize.applying(t)
        let srcSize = CGSize(width: abs(sizeApplied.width), height: abs(sizeApplied.height))
        let target = renderSize

        let dx = max((srcSize.width - target.width) / 2, 0).rounded()
        let dy = max((srcSize.height - target.height) / 2, 0).rounded()
        let crop = CGAffineTransform(translationX: -dx, y: -dy)
        return t.concatenating(crop)
    }
}


