import SwiftUI
import AVKit
import AVFoundation

/// Video preview with live text overlay rendering during editing.
struct EditorTrackArea: View {
    @ObservedObject var state: EditorState
    @Binding var canvasRect: CGRect
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Chrome-free playback surface (no system controls)
                PlayerSurface(player: state.player, videoGravity: .resizeAspect)
                    .background(Color.black)

                // Render visible text overlays in canvas coordinate space
                ZStack {
                    ForEach(Array(state.textOverlays.enumerated()), id: \.element.id) { idx, t in
                        if isVisible(t, at: state.currentTime) {
                            let base = state.textOverlays[idx].base
                            overlayText(base)
                                .position(x: base.position.x, y: base.position.y)
                                .scaleEffect(base.scale)
                                .rotationEffect(Angle(radians: Double(base.rotation)))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .onAppear { canvasRect = CGRect(origin: .zero, size: geo.size) }
            .onChange(of: geo.size) { newSize in
                canvasRect = CGRect(origin: .zero, size: newSize)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func overlayText(_ model: TextOverlay) -> some View {
        let font: Font = {
            switch model.style {
            case .small: return .system(size: 24, weight: .regular)
            case .largeCenter, .largeBackground: return .system(size: 42, weight: .bold)
            }
        }()
        return Text(model.string.isEmpty ? " " : model.string)
            .font(font)
            .foregroundColor(model.color.color)
            .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
    }

    private func isVisible(_ t: TimedTextOverlay, at time: CMTime) -> Bool {
        guard time.isNumeric else { return false }
        let start = t.start
        let end = t.start + t.duration
        return time >= start && time <= end
    }
}


