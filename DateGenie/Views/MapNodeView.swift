import SwiftUI

/// Single circular node used in AdventureMapView showing a star that can be pending, active (flashing) or done (solid gold).
struct MapNodeView: View {
    enum NodeStatus { case pending, active, done }

    let size: CGFloat
    let status: NodeStatus

    @State private var pulse: Bool

    // Explicit initializer (also initializes the @State wrapper)
    init(size: CGFloat, status: NodeStatus) {
        self.size = size
        self.status = status
        _pulse = SwiftUI.State(initialValue: false)
    }

    var body: some View {
        ZStack {
            // bottom shadow circle
            Circle()
                .fill(Color.nodeBottom)
                .frame(width: size, height: size)
                .offset(x: size * 0.08, y: size * 0.12)

            // top circle
            Circle()
                .fill(Color.nodeTop)
                .frame(width: size, height: size)

            // Base star (outline or filled)
            if status == .done {
                Image(systemName: "star.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.6)
                    .foregroundColor(.yellow)
            } else {
                Image(systemName: "star")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.6)
                    .foregroundColor(.white)
                // Blinking overlay when active
                if status == .active {
                    Image(systemName: "star.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.6)
                        .foregroundColor(.yellow)
                        .opacity(pulse ? 0.2 : 1)
                        .onAppear {
                            // start pulse animation
                            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                                pulse.toggle()
                            }
                        }
                }
            }
        }
        // extra frame to give space similar to previous implementation
        .frame(width: size * 1.3, height: size * 1.3, alignment: .top)
    }
}
