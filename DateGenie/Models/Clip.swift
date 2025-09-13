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

    // Speed / pitch controls (Standard speed)
    /// Playback speed multiplier. 1.0 = normal speed. UI clamps 0.2…100.
    var speed: Double = 1.0
    /// Preserve pitch of original embedded audio when speed != 1.0.
    var preserveOriginalPitch: Bool = true
    /// Placeholder for future motion smoothing (UI-only for now)
    var smoothInterpolation: Bool = false

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

    /// On-timeline effective duration after trimming and speed retime.
    var effectiveDuration: CMTime {
        guard speed > 0 else { return .zero }
        let seconds = CMTimeGetSeconds(trimmedDuration) / speed
        return CMTime(seconds: max(0, seconds), preferredTimescale: 600)
    }
}


