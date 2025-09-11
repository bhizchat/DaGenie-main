 import SwiftUI

struct ColorSlider: View {
    @Binding var color: Color
    // Notify parent when user is dragging so it can temporarily disable underlying hit-testing
    var onDragChanged: ((Bool) -> Void)? = nil
    // simple hue slider with optional horizontal brightness drift
    @State private var hue: CGFloat = 0.0
    @State private var brightness: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                LinearGradient(gradient: Gradient(colors: stride(from: 0.0, through: 1.0, by: 0.1).map { Color(hue: $0, saturation: 1, brightness: 1) }), startPoint: .top, endPoint: .bottom)
                    .cornerRadius(8)
                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .shadow(radius: 2)
                    .offset(y: CGFloat(hue) * (geo.size.height - 24))
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    onDragChanged?(true)
                    let y = max(0, min(geo.size.height, g.location.y))
                    hue = min(1, max(0, y / geo.size.height))
                    // brightness drift: drag left reduces brightness
                    let drift = max(-80, min(80, g.location.x - geo.size.width/2))
                    let b = 1.0 - (abs(drift) / 80.0) * 0.5
                    brightness = CGFloat(max(0.5, b))
                    color = Color(hue: Double(hue), saturation: 1.0, brightness: Double(brightness))
                }
                .onEnded { _ in onDragChanged?(false) }
            )
        }
        .frame(width: 36)
    }
}


