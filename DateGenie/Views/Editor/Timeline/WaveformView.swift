import SwiftUI

struct WaveformView: View {
    let samples: [Float]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let width = max(1, Int(geo.size.width))
            let count = samples.count
            let step = max(1, count / width)
            Path { path in
                let midY = geo.size.height / 2
                var x: CGFloat = 0
                var i = 0
                while i < count {
                    let sample = samples[i]
                    let amp = CGFloat(sample) * (geo.size.height / 2)
                    path.move(to: CGPoint(x: x, y: midY - amp))
                    path.addLine(to: CGPoint(x: x, y: midY + amp))
                    x += 1
                    i += step
                }
            }
            .stroke(color.opacity(0.9), lineWidth: 1)
        }
    }
}


