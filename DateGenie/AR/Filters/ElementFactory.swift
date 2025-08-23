import Foundation
import RealityKit
import UIKit

enum ElementFactory {
    /// Create a RealityKit entity for the given filter element.
    /// For models this loads asynchronously from a bundled usdz.
    static func makeEntity(from element: FilterElement) async throws -> Entity {
        switch element.kind {
        case .sticker2D:
            return try await makeSticker2D(element: element)
        case .model3D:
            return try await makeModel3D(named: element.assetName, defaultScale: element.defaultScale)
        }
    }

    private static func makeSticker2D(element: FilterElement) async throws -> Entity {
        let plane = MeshResource.generatePlane(width: element.defaultScale, height: element.defaultScale)
        // Use UnlitMaterial so alpha is respected and lighting doesn't darken the sticker
        var unlit = UnlitMaterial()
        // Generate exclusively from UI thumbnail (Image Set) to bypass Texture Set path entirely
        if let uiName = element.uiThumbnailName,
           let ui = UIImage(named: uiName),
           let cg = ui.cgImage,
           let gen = try? await TextureResource.generate(from: cg, options: .init(semantic: .color)) {
            unlit.color = .init(texture: .init(gen))
            // Enable proper alpha blending in RealityKit (opaque by default)
            if #available(iOS 17.0, *) {
                unlit.blending = .transparent(opacity: 1.0)
            } else {
                // Fallback hack for older RealityKit: slightly < 1 alpha on tint to trigger blending
                var color = unlit.color
                color.tint = UIColor(white: 1.0, alpha: 0.999)
                unlit.color = color
            }
        } else {
            // Fallback: solid white if UI asset missing
            unlit.color = .init(tint: .white)
        }
        // Rely on alpha in the texture; omit explicit blending to keep cross-version compatibility
        let model = ModelEntity(mesh: plane, materials: [unlit])
        model.name = element.assetName
        model.generateCollisionShapes(recursive: true)
        // Face the camera for sticker-type overlays
        if #available(iOS 18.0, *) { model.components[BillboardComponent.self] = BillboardComponent() }
        return model
    }

    private static func makeModel3D(named name: String, defaultScale: Float) async throws -> Entity {
        // Async load from app bundle. Callers should ensure the asset exists.
        let entity = try Entity.loadModel(named: name)
        entity.scale *= [defaultScale, defaultScale, defaultScale]
        entity.generateCollisionShapes(recursive: true)
        return entity
    }
}

private extension SIMD3 where Scalar == Float {
    static func *=(lhs: inout Self, rhs: Self) { lhs = .init(lhs.x * rhs.x, lhs.y * rhs.y, lhs.z * rhs.z) }
}


