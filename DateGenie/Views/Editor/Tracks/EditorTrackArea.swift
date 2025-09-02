import SwiftUI
import AVKit
import AVFoundation

/// Video preview with live text overlay rendering during editing.
struct EditorTrackArea: View {
    @ObservedObject var state: EditorState
    @Binding var canvasRect: CGRect
    // Local focus holder to satisfy TextOverlayView's FocusState binding
    @FocusState private var localFocusedTextId: UUID?
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
                            if state.selectedTextId == t.id {
                                // Interactive rendering for the selected overlay
                                TextOverlayView(
                                    model: $state.textOverlays[idx].base,
                                    isEditing: false,
                                    onBeginEdit: {},
                                    onEndEdit: {},
                                    activeTextId: $localFocusedTextId,
                                    canvasSize: geo.size
                                )
                                .allowsHitTesting(true)
                            } else {
                                let base = state.textOverlays[idx].base
                                overlayText(base)
                                    .position(x: base.position.x, y: base.position.y)
                                    .scaleEffect(base.scale)
                                    .rotationEffect(Angle(radians: Double(base.rotation)))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        state.selectedTextId = t.id
                                        // Open edit toolbar when selecting a text overlay
                                        DispatchQueue.main.async {
                                            NotificationCenter.default.post(name: Notification.Name("OpenEditToolbarForSelection"), object: nil)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .coordinateSpace(name: "canvas")
            .onAppear { canvasRect = CGRect(origin: .zero, size: geo.size) }
            .onChange(of: geo.size) { newSize in
                canvasRect = CGRect(origin: .zero, size: newSize)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DeleteSelectedTextOverlay"))) { _ in
            if let id = state.selectedTextId, let idx = state.textOverlays.firstIndex(where: { $0.id == id }) {
                state.textOverlays.remove(at: idx)
                state.selectedTextId = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DuplicateSelectedTextOverlay"))) { note in
            guard let id = note.object as? UUID, let idx = state.textOverlays.firstIndex(where: { $0.id == id }) else { return }
            var src = state.textOverlays[idx]
            var dup = src
            dup.base = TextOverlay(id: UUID(), string: src.base.string, fontName: src.base.fontName, style: src.base.style, color: src.base.color, position: CGPoint(x: min(src.base.position.x + 16, canvasRect.width), y: min(src.base.position.y + 16, canvasRect.height)), scale: src.base.scale, rotation: src.base.rotation, zIndex: src.base.zIndex + 1)
            state.textOverlays.append(dup)
            state.selectedTextId = dup.id
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UnselectTextOverlay"))) { _ in
            state.selectedTextId = nil
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("CloseEditToolbarForDeselection"), object: nil)
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


