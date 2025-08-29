import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

#if canImport(Vision)
import Vision
#endif

/// Background removal utility for onboarding logos.
/// - Prefers Vision foreground mask on iOS 17+ (on-device, no network).
/// - Falls back to a fast near-white chroma key using CoreGraphics.
enum BackgroundRemoval {
    /// Asynchronously removes the background from the provided image.
    /// The completion is called on the main thread with a UIImage that preserves transparency.
    static func removeBackground(from image: UIImage, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result: UIImage?
#if USE_VN_FG_MASK && compiler(>=5.9)
            if #available(iOS 17.0, *) {
                result = visionCutout(image)
            } else {
                result = thresholdCutout(image)
            }
#else
            result = thresholdCutout(image)
#endif
            DispatchQueue.main.async { completion(result) }
        }
    }

// NOTE:
// The iOS 17 Vision foreground instance mask APIs are only available when building
// with the iOS 17 SDK (Xcode 15+). To avoid compile errors on older SDKs, this
// block is additionally gated behind the custom Swift flag `USE_VN_FG_MASK`.
// Enable it in Build Settings -> Other Swift Flags for configurations that use the iOS 17 SDK.
#if USE_VN_FG_MASK && compiler(>=5.9)
    @available(iOS 17.0, *)
    private static func visionCutout(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let ciContext = CIContext(options: nil)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return thresholdCutout(image)
        }

        guard let obs = request.results?.first as? VNForegroundInstanceMaskObservation else { return thresholdCutout(image) }
        guard let pb = try? obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler) else { return thresholdCutout(image) }

        let inputCI = CIImage(cgImage: cg)
        let maskCI = CIImage(cvPixelBuffer: pb)

        let transparent = CIImage(color: .clear).cropped(to: inputCI.extent)
        guard let filter = CIFilter(name: "CIBlendWithMask") else { return thresholdCutout(image) }
        filter.setValue(inputCI, forKey: kCIInputImageKey)
        filter.setValue(transparent, forKey: kCIInputBackgroundImageKey)
        filter.setValue(maskCI, forKey: kCIInputMaskImageKey)
        guard let output = filter.outputImage, let cgOut = ciContext.createCGImage(output, from: output.extent) else { return thresholdCutout(image) }
        return UIImage(cgImage: cgOut, scale: image.scale, orientation: image.imageOrientation)
    }
#endif

    /// Fast near-white removal using CoreGraphics color masking.
    private static func thresholdCutout(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        // Treat very light tones as background; tune as needed.
        let range: [CGFloat] = [200, 255, 200, 255, 200, 255]
        guard let masked = cg.copy(maskingColorComponents: range) else { return image }
        return UIImage(cgImage: masked, scale: image.scale, orientation: image.imageOrientation)
    }
}
