import SwiftUI
import UIKit

/// Lightweight confetti using CAEmitterLayer. No external dependency required.
struct ConfettiView: UIViewRepresentable {
    var colors: [UIColor] = [.systemPink, .systemYellow, .systemGreen, .systemBlue, .systemPurple]
    var intensity: Float = 0.6
    var duration: TimeInterval = 2.0

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: UIScreen.main.bounds.width / 2, y: -10)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: UIScreen.main.bounds.width, height: 2)
        emitter.beginTime = CACurrentMediaTime()

        var cells: [CAEmitterCell] = []
        for color in colors {
            let cell = CAEmitterCell()
            cell.birthRate = 8 * intensity
            cell.lifetime = 6.0
            cell.lifetimeRange = 1.0
            cell.velocity = 220
            cell.velocityRange = 80
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 4
            cell.spin = 3.5
            cell.spinRange = 4.0
            cell.scale = 0.6
            cell.scaleRange = 0.3
            cell.contents = UIImage(systemName: "circle.fill")?.withTintColor(color, renderingMode: .alwaysOriginal).cgImage
            cells.append(cell)
        }
        emitter.emitterCells = cells
        view.layer.addSublayer(emitter)

        // Stop emission after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            emitter.birthRate = 0
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}


