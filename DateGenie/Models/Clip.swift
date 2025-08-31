import Foundation
import AVFoundation
import UIKit

/// Represents a single video clip on the editor timeline.
struct Clip: Identifiable, Equatable {
    let id: UUID = UUID()
    let url: URL
    let asset: AVAsset
    let duration: CMTime

    // Filmstrip visuals for this clip
    var thumbnails: [UIImage] = []
    var thumbnailTimes: [CMTime] = []
    // Pixels-per-second used when generating thumbnails (for caching/regen decisions)
    var thumbnailPPS: CGFloat = 0

    // Audio visualization and control
    var hasOriginalAudio: Bool = true
    var waveformSamples: [Float] = []
}


