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
    /// When true, the original audio embedded in the video is muted in preview/export composition
    var muteOriginalAudio: Bool = false
    /// Per-clip gain for original embedded audio. UI 50% defaults to 0.5 here.
    var originalAudioVolume: Float = 0.5

    // Trimming (selection) – offsets within original asset duration
    // start offset in seconds from beginning of asset
    var trimStart: CMTime = .zero
    // end time within asset; nil means use full duration
    var trimEnd: CMTime? = nil

    /// Effective duration after trimming. Guaranteed ≥ .zero
    var trimmedDuration: CMTime {
        let end = trimEnd ?? duration
        let dur = end - trimStart
        return dur >= .zero ? dur : .zero
    }
}


