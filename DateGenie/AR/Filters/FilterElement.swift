import Foundation

/// Describes a single placeable AR element (your "custom filter").
/// Users can manipulate one active element before capture.
public struct FilterElement: Identifiable, Hashable {
    public enum Kind: String, Codable { case sticker2D, model3D }

    public let id: String
    public let name: String
    public let kind: Kind

    /// For stickers: image name in assets. For models: bundled usdz name (or file name in app bundle).
    public let assetName: String

    /// Default visual scale at spawn time.
    /// - For stickers: plane width/height in meters (square).
    /// - For models: multiplicative factor applied to the model's native units.
    public let defaultScale: Float

    public let allowsDrag: Bool
    public let allowsRotate: Bool
    public let allowsScale: Bool

    /// If true, the element should face the camera each frame (best for stickers/logos).
    public let billboard: Bool
    /// Optional animation identifier for models (future use).
    public let animation: String?
    /// Optional name of an Image Set for UI thumbnails (do not use for RealityKit textures).
    public let uiThumbnailName: String?

    public init(id: String = UUID().uuidString,
                name: String,
                kind: Kind,
                assetName: String,
                defaultScale: Float = 0.2,
                allowsDrag: Bool = true,
                allowsRotate: Bool = true,
                allowsScale: Bool = true,
                billboard: Bool = false,
                animation: String? = nil,
                uiThumbnailName: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.assetName = assetName
        self.defaultScale = defaultScale
        self.allowsDrag = allowsDrag
        self.allowsRotate = allowsRotate
        self.allowsScale = allowsScale
        self.billboard = billboard
        self.animation = animation
        self.uiThumbnailName = uiThumbnailName
    }
}


