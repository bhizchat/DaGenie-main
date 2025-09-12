import CoreGraphics
import AVFoundation

enum AspectRatio {
    case original
    case nineBySixteen
    case sixteenByNine
    case fourByFive
    case oneByOne
    case threeByFour
    case fourByThree

    // width / height. nil means keep original aspect
    var value: CGFloat? {
        switch self {
        case .original: return nil
        case .nineBySixteen: return 9.0/16.0
        case .sixteenByNine: return 16.0/9.0
        case .fourByFive: return 4.0/5.0
        case .oneByOne: return 1.0
        case .threeByFour: return 3.0/4.0
        case .fourByThree: return 4.0/3.0
        }
    }
}

enum ContentMode {
    case fill      // center-crop (CapCut default)
    case fit       // letterbox/pillarbox
}

struct VideoRenderConfig {
    var aspect: AspectRatio
    var mode: ContentMode

    init(aspect: AspectRatio = .original, mode: ContentMode = .fill) {
        self.aspect = aspect
        self.mode = mode
    }

    func renderSize(for sourceSize: CGSize) -> CGSize {
        switch mode {
        case .fill:
            return cropCenterRenderSize(for: sourceSize)
        case .fit:
            // Keep source; presentation shows bars
            return sourceSize
        }
    }

    private func cropCenterRenderSize(for sourceSize: CGSize) -> CGSize {
        guard let targetAR = aspect.value else { return sourceSize }
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


