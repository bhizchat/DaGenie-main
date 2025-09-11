import SwiftUI
import AVFoundation
import UIKit

/// Timeline-specific lightweight models that map to our existing overlays.
/// These are used for layout/interaction only and are translated back to
/// TimedTextOverlay / TimedCaption / AudioTrack after edits.

enum TrackKind: String {
    case video
    case audio
    case text
}

struct Track: Identifiable, Equatable {
    let id: UUID = UUID()
    var kind: TrackKind
    var items: [TrackItem]
}

enum TrackItemType: Equatable {
    case audio(sourceId: UUID)
    case text(sourceId: UUID)
    case caption(sourceId: UUID)
}

struct TrackItem: Identifiable, Equatable {
    let id: UUID = UUID()
    var type: TrackItemType
    var start: CMTime
    var duration: CMTime
    var color: Color = .white
}

// (Removed temporary UI-only models during revert)


