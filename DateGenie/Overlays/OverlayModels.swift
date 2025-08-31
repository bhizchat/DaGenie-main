import Foundation
import SwiftUI
import PencilKit
import AVFoundation

enum OverlayMode: Equatable {
    case none
    case textInsert
    case textEdit(id: UUID)
    case draw
}

enum TextStyle: String, Codable {
    case small
    case largeCenter
    case largeBackground
}

struct RGBAColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1.0) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(_ color: Color) {
        let ui = UIColor(color)
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        ui.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        self.r = Double(rr); self.g = Double(gg); self.b = Double(bb); self.a = Double(aa)
    }
    var color: Color { Color(red: r, green: g, blue: b, opacity: a) }
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
}

struct TextOverlay: Identifiable, Codable, Equatable {
    let id: UUID
    var string: String
    var fontName: String
    var style: TextStyle
    var color: RGBAColor
    var position: CGPoint   // in canvas points
    var scale: CGFloat
    var rotation: CGFloat   // radians
    var zIndex: Int

    init(id: UUID = UUID(), string: String, fontName: String = "System", style: TextStyle = .small, color: RGBAColor = RGBAColor(r: 1, g: 1, b: 1, a: 1), position: CGPoint, scale: CGFloat = 1.0, rotation: CGFloat = 0, zIndex: Int = 0) {
        self.id = id
        self.string = string
        self.fontName = fontName
        self.style = style
        self.color = color
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.zIndex = zIndex
    }
}

struct OverlayState {
    var mode: OverlayMode = .none
    var texts: [TextOverlay] = []
    var drawing: PKDrawing = PKDrawing()
    var lastTextColor: Color = .white
    var lastDrawColor: Color = .white
    // Snapchat-style caption bar state (non-optional; visibility controlled by flag)
    var caption: CaptionModel = CaptionModel.default()
}

// Helpers
func aspectFitRect(contentSize: CGSize, in container: CGRect) -> CGRect {
    let fit = AVMakeRect(aspectRatio: contentSize, insideRect: container)
    return fit.integral
}

// MARK: - Caption
struct CaptionModel: Codable, Equatable {
    var text: String
    var fontName: String
    var fontSize: CGFloat
    var textColor: RGBAColor
    var backgroundColor: RGBAColor
    /// 0...1 position within canvas height, measured from canvas.minY
    var verticalOffsetNormalized: CGFloat
    var isVisible: Bool

    static func `default`() -> CaptionModel {
        CaptionModel(
            text: "",
            fontName: "System",
            fontSize: 18,
            textColor: RGBAColor(r: 1, g: 1, b: 1, a: 1),
            backgroundColor: RGBAColor(r: 0, g: 0, b: 0, a: 0.5),
            verticalOffsetNormalized: 0.8,
            isVisible: false
        )
    }
}// MARK: - Timed Overlays (non-breaking wrappers)
/// Timed wrapper for text overlays without changing existing `TextOverlay` Codable.
struct TimedTextOverlay: Identifiable, Equatable {
    var id: UUID { base.id }
    var base: TextOverlay
    var start: CMTime
    var duration: CMTime

    init(base: TextOverlay, start: CMTime, duration: CMTime) {
        self.base = base
        self.start = start
        self.duration = duration
    }
}

/// Timed wrapper for captions based on existing `CaptionModel`.
struct TimedCaption: Identifiable, Equatable {
    let id: UUID = UUID()
    var base: CaptionModel
    var start: CMTime
    var duration: CMTime
}

/// Simple representation of an added background audio track.
struct AudioTrack: Identifiable, Equatable {
    let id: UUID = UUID()
    var url: URL
    var start: CMTime
    var duration: CMTime
    var volume: Float
}


