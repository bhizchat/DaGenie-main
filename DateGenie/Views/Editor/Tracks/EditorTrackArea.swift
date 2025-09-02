import SwiftUI
import AVKit
import AVFoundation

/// Video preview with live text overlay rendering during editing.
struct EditorTrackArea: View {
    @ObservedObject var state: EditorState
    @Binding var canvasRect: CGRect
    // Local focus holder to satisfy TextOverlayView's FocusState binding
    @FocusState private var localFocusedTextId: UUID?
    // Canvas-wide transform gesture state (applies to selected text)
    @GestureState private var canvasMagnify: CGFloat = 1
    @GestureState private var canvasRotate: Angle = .zero
    @State private var canvasAnchor: UnitPoint = .center
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Chrome-free playback surface (no system controls)
                PlayerSurface(player: state.player, videoGravity: .resizeAspect)
                    .background(Color.black)

                // Render visible text overlays in canvas coordinate space
                ZStack {
                    ForEach(state.textOverlays, id: \ .id) { t in
                        if isVisible(t, at: state.currentTime) {
                            if state.selectedTextId == t.id {
                                if let i = state.textOverlays.firstIndex(where: { $0.id == t.id }) {
                                    TextOverlayView(
                                        model: $state.textOverlays[i].base,
                                        externalScaleDelta: canvasMagnify,
                                        externalRotationDelta: canvasRotate,
                                        externalAnchor: canvasAnchor,
                                        enableInternalTransformGesture: false,
                                        isEditing: false,
                                        onBeginEdit: {},
                                        onEndEdit: {},
                                        activeTextId: $localFocusedTextId,
                                        canvasSize: geo.size
                                    )
                                    .allowsHitTesting(true)
                                }
                            } else {
                                let base = t.base
                                overlayText(base)
                                    .position(x: base.position.x, y: base.position.y)
                                    .scaleEffect(base.scale)
                                    .rotationEffect(Angle(radians: Double(base.rotation)))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        state.selectedTextId = t.id
                                        DispatchQueue.main.async {
                                            NotificationCenter.default.post(name: Notification.Name("OpenEditToolbarForSelection"), object: nil)
                                        }
                                    }
                            }
                        }
                    }
                }
                // Full-canvas gesture layer: active only when a text is selected
                .overlay(alignment: .center) {
                    if state.selectedTextId != nil {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(canvasTransformGesture(), including: .gesture)
                    }
                }
            }
            .coordinateSpace(name: "canvas")
            .onAppear { canvasRect = CGRect(origin: .zero, size: geo.size) }
            .onChange(of: geo.size) { newSize in
                canvasRect = CGRect(origin: .zero, size: newSize)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DeleteSelectedTextOverlay"))) { note in
            guard let id = (note.object as? UUID) ?? state.selectedTextId else { return }
            if let idx = state.textOverlays.firstIndex(where: { $0.id == id }) {
                state.textOverlays.remove(at: idx)
                if state.selectedTextId == id { state.selectedTextId = nil }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DuplicateSelectedTextOverlay"))) { note in
            guard let id = note.object as? UUID,
                  let idx = state.textOverlays.firstIndex(where: { $0.id == id }) else { return }
            let src = state.textOverlays[idx]
            var dup = src
            dup.base = TextOverlay(id: UUID(),
                                   string: src.base.string,
                                   fontName: src.base.fontName,
                                   style: src.base.style,
                                   color: src.base.color,
                                   position: CGPoint(x: min(src.base.position.x + 16, canvasRect.width),
                                                     y: min(src.base.position.y + 16, canvasRect.height)),
                                   scale: src.base.scale,
                                   rotation: src.base.rotation,
                                   zIndex: src.base.zIndex + 1)
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

// MARK: - Canvas transform gesture (selected text only)
extension EditorTrackArea {
    private func canvasTransformGesture() -> some Gesture {
        if #available(iOS 17, *) {
            return SimultaneousGesture(
                MagnifyGesture(minimumScaleDelta: 0.005)
                    .updating($canvasMagnify) { value, state, _ in
                        state = value.magnification
                        canvasAnchor = value.startAnchor
                    }
                    .onEnded { value in
                        commitScaleDelta(value.magnification)
                    },
                RotationGesture()
                    .updating($canvasRotate) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        commitRotationDelta(value)
                    }
            )
        } else {
            return SimultaneousGesture(
                MagnificationGesture()
                    .updating($canvasMagnify) { value, state, _ in state = value }
                    .onEnded { value in commitScaleDelta(value) },
                RotationGesture()
                    .updating($canvasRotate) { value, state, _ in state = value }
                    .onEnded { value in commitRotationDelta(value) }
            )
        }
    }

    private func commitScaleDelta(_ scaleDelta: CGFloat) {
        guard let id = state.selectedTextId,
              let i = state.textOverlays.firstIndex(where: { $0.id == id }),
              scaleDelta.isFinite, scaleDelta > 0.001 else { return }
        let clamped = max(0.2, min(6.0, state.textOverlays[i].base.scale * scaleDelta))
        state.textOverlays[i].base.scale = clamped
    }

    private func commitRotationDelta(_ delta: Angle) {
        guard let id = state.selectedTextId,
              let i = state.textOverlays.firstIndex(where: { $0.id == id }),
              delta.radians.isFinite else { return }
        state.textOverlays[i].base.rotation += CGFloat(delta.radians)
    }
}


