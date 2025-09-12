import SwiftUI
import UIKit
import ImageIO

/// SwiftUI wrapper for rendering animated GIFs stored as "Data" assets in the asset catalog
/// Usage: GIFImage(dataAssetName: "memeverse_heartbeat")
struct GIFImage: UIViewRepresentable {
    let dataAssetName: String
    let contentMode: UIView.ContentMode

    init(dataAssetName: String, contentMode: UIView.ContentMode = .scaleAspectFit) {
        self.dataAssetName = dataAssetName
        self.contentMode = contentMode
    }

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = contentMode
        imageView.clipsToBounds = true
        if let asset = NSDataAsset(name: dataAssetName),
           let animated = UIImage.animatedImage(withGIFData: asset.data) {
            imageView.image = animated
        }
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) { }
}

private extension UIImage {
    static func animatedImage(withGIFData data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let frameCount = CGImageSourceGetCount(source)
        var images: [UIImage] = []
        var duration: Double = 0
        images.reserveCapacity(frameCount)
        for i in 0..<frameCount {
            if let cg = CGImageSourceCreateImageAtIndex(source, i, nil) {
                let frameDuration = Self.frameDuration(at: i, source: source)
                duration += frameDuration
                images.append(UIImage(cgImage: cg))
            }
        }
        if duration == 0 { duration = Double(max(frameCount, 1)) * 0.1 }
        return UIImage.animatedImage(with: images, duration: duration)
    }

    static func frameDuration(at index: Int, source: CGImageSource) -> Double {
        var duration: Double = 0.1
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifDict = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return duration }
        if let unclamped = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? Double {
            duration = unclamped
        } else if let clamped = gifDict[kCGImagePropertyGIFDelayTime] as? Double {
            duration = clamped
        }
        if duration < 0.011 { duration = 0.1 }
        return duration
    }
}


