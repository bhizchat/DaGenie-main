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

    // Audio visualization and control
    var hasOriginalAudio: Bool = true
    var waveformSamples: [Float] = []
}


