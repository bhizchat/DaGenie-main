import CoreGraphics

enum VideoRenderConfig {
    // Overall zoom applied during final export and preview. 1.0 = none.
    // Disable zoom; framing is now controlled by 4:5 cropping.
    static let exportZoomScale: CGFloat = 1.0
}


