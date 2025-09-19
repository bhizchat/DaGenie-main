import UIKit

@MainActor
enum WebcomicExporter {
    struct PanelSpec { let image: UIImage }

    /// Builds a single tall PNG at 800px width that stacks scene images vertically.
    /// - Returns: File URL to a temporary PNG
    static func export(plan: StoryboardPlan, width: CGFloat = 800, panelSpacing: CGFloat = 24) async throws -> URL {
        // Load images for scenes in order
        var panels: [PanelSpec] = []
        for s in plan.scenes.sorted(by: { $0.index < $1.index }) {
            guard let urlStr = s.imageUrl, let url = URL(string: urlStr), let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { continue }
            panels.append(PanelSpec(image: img))
        }
        guard !panels.isEmpty else { throw NSError(domain: "WebcomicExporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "No panels with images"]) }

        // Precompute scaled sizes
        let scaleFactor: (UIImage) -> CGFloat = { img in width / max(1, img.size.width) }
        var totalHeight: CGFloat = 0
        var scaledHeights: [CGFloat] = []
        for p in panels {
            let k = scaleFactor(p.image)
            let h = p.image.size.height * k
            scaledHeights.append(h)
            totalHeight += h
            if panels.firstIndex(where: { $0.image === p.image })! < panels.count - 1 { totalHeight += panelSpacing }
        }

        // Draw
        let size = CGSize(width: width, height: ceil(totalHeight))
        UIGraphicsBeginImageContextWithOptions(size, true, 2.0)
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

        var y: CGFloat = 0
        for i in 0..<panels.count {
            let p = panels[i]
            let h = scaledHeights[i]
            let imgRect = CGRect(x: 0, y: y, width: width, height: h)
            p.image.draw(in: imgRect)
            y += h
            if i < panels.count - 1 { y += panelSpacing }
        }

        let finalImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        guard let png = finalImage?.pngData() else { throw NSError(domain: "WebcomicExporter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to render image"]) }

        let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("webcomic_\(UUID().uuidString).png")
        try png.write(to: out)
        return out
    }
}


