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
    // Canvas-wide drag state to move selected text from anywhere on the screen
    @GestureState private var canvasDragTranslation: CGSize = .zero
    @State private var dragStartPosition: CGPoint? = nil
    var body: some View {
        GeometryReader { geo in
            // Compute a fitted canvas rect that preserves the selected project aspect.
            let targetAR: CGFloat = {
                if let ar = state.renderConfig.aspect.value { return ar }
                // Fallback to first clip's oriented aspect
                if let t = state.player.currentItem?.asset.tracks(withMediaType: .video).first {
                    let r = CGRect(origin: .zero, size: t.naturalSize).applying(t.preferredTransform)
                    let w = abs(r.width), h = abs(r.height)
                    if w > 0 && h > 0 { return w / h }
                }
                return 9.0/16.0
            }()
            let fit = AVMakeRect(aspectRatio: CGSize(width: max(targetAR, 0.0001), height: 1), insideRect: CGRect(origin: .zero, size: geo.size))

            ZStack {
                // Chrome-free playback surface (no system controls) sized to the fitted canvas
                PlayerSurface(player: state.player,
                              videoGravity: (state.renderConfig.mode == .fit ? .resizeAspect : .resizeAspectFill))
                    .background(Color.black)
                    .frame(width: fit.width, height: fit.height)

                // Render visible text overlays in canvas coordinate space
                ZStack {
                    // Media overlays: selected uses canvas-wide magnify/rotate deltas; others are passive
                    ForEach(state.mediaOverlays, id: \.id) { m in
                        if isVisible(m, at: state.displayTime) {
                            if state.selectedMediaId == m.id {
                                if let i = state.mediaOverlays.firstIndex(where: { $0.id == m.id }) {
                                    MediaOverlayView(
                                        model: $state.mediaOverlays[i],
                                        canvasSize: fit.size,
                                        externalScaleDelta: canvasMagnify,
                                        externalRotationDelta: canvasRotate,
                                        externalAnchor: canvasAnchor,
                                        enableInternalTransformGesture: false,
                                        showSelectionChips: true
                                    )
                                        .allowsHitTesting(true)
                                }
                            } else {
                                if let i = state.mediaOverlays.firstIndex(where: { $0.id == m.id }) {
                                    MediaOverlayView(
                                        model: $state.mediaOverlays[i],
                                        canvasSize: fit.size,
                                        externalScaleDelta: 1,
                                        externalRotationDelta: .zero,
                                        externalAnchor: .center,
                                        enableInternalTransformGesture: false,
                                        showSelectionChips: false
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        state.selectedMediaId = m.id
                                        state.selectedTextId = nil
                                        state.selectedClipId = nil
                                        state.selectedAudioId = nil
                                        DispatchQueue.main.async { NotificationCenter.default.post(name: Notification.Name("OpenEditToolbarForSelection"), object: nil) }
                                    }
                                }
                            }
                        }
                    }
                    ForEach(state.textOverlays, id: \.id) { t in
                        if isVisible(t, at: state.displayTime) {
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
                                        canvasSize: fit.size
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
                .coordinateSpace(name: "canvas")
                // Full-canvas overlay (non-hittable) keeps layout predictable
                .overlay(alignment: .center) {
                    if state.selectedTextId != nil {
                        Rectangle()
                            .fill(Color.clear)
                            .allowsHitTesting(false)
                    }
                }
            }
            // Center the canvas inside available geometry
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            // Make the entire canvas area the gesture target (not just over the text)
            .contentShape(Rectangle())
            .modifier(SelectedTransformGestureModifier(isActive: state.selectedTextId != nil || state.selectedMediaId != nil, gestureProvider: { canvasTransformGesture() }))
            .onAppear { canvasRect = CGRect(origin: .zero, size: fit.size) }
            .onChange(of: geo.size) { _ in
                canvasRect = CGRect(origin: .zero, size: fit.size)
            }
            .onChange(of: state.renderConfig.aspect) { _ in
                canvasRect = CGRect(origin: .zero, size: fit.size)
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DeleteSelectedMediaOverlay"))) { note in
            guard let id = (note.object as? UUID) ?? state.selectedMediaId else { return }
            if let idx = state.mediaOverlays.firstIndex(where: { $0.id == id }) {
                state.mediaOverlays.remove(at: idx)
                if state.selectedMediaId == id { state.selectedMediaId = nil }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DuplicateSelectedMediaOverlay"))) { note in
            guard let id = note.object as? UUID,
                  let idx = state.mediaOverlays.firstIndex(where: { $0.id == id }) else { return }
            let src = state.mediaOverlays[idx]
            // Duplicate in-place (common editor behavior) with a slight canvas nudge
            let newStart = src.start
            let dup = TimedMediaOverlay(
                url: src.url,
                kind: src.kind,
                position: CGPoint(x: min(src.position.x + 16, canvasRect.width),
                                  y: min(src.position.y + 16, canvasRect.height)),
                scale: src.scale,
                rotation: src.rotation,
                alpha: src.alpha,
                zIndex: src.zIndex + 1,
                start: newStart,
                duration: src.duration,
                trimStart: src.trimStart,
                trimEnd: src.trimEnd
            )
            state.mediaOverlays.append(dup)
            state.selectedMediaId = dup.id
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UnselectTextOverlay"))) { _ in
            state.selectedTextId = nil
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("CloseEditToolbarForDeselection"), object: nil)
            }
            // Ensure timeline scrolling is re-enabled even if gestures were cancelled mid-flight
            // by signalling the container to clear any drag gate.
            NotificationCenter.default.post(name: Notification.Name("ResetTimelineDragGate"), object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UnselectMediaOverlay"))) { _ in
            state.selectedMediaId = nil
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("CloseEditToolbarForDeselection"), object: nil)
            }
            NotificationCenter.default.post(name: Notification.Name("ResetTimelineDragGate"), object: nil)
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
        let start = t.effectiveStart
        let end = t.effectiveStart + t.trimmedDuration
        return time >= start && time <= end
    }

    private func isVisible(_ m: TimedMediaOverlay, at time: CMTime) -> Bool {
        guard time.isNumeric else { return false }
        let start = m.effectiveStart
        let end = m.effectiveStart + m.trimmedDuration
        return time >= start && time <= end
    }
}

// MARK: - Canvas transform gesture (selected text only)
extension EditorTrackArea {
    private func canvasTransformGesture() -> AnyGesture<Void> {
        if #available(iOS 17, *) {
            // Global pinch: scales currently selected text even if the gesture starts away from it
            let pinch = MagnifyGesture(minimumScaleDelta: 0.003)
                .updating($canvasMagnify) { value, state, _ in
                    state = value.magnification
                    canvasAnchor = value.startAnchor
                }
                .onEnded { value in
                    commitScaleDelta(value.magnification)
                }

            // Global rotate: rotates the selected text regardless of touch location
            let rotate = RotationGesture()
                .updating($canvasRotate) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    commitRotationDelta(value)
                }

            // Match text overlay drag semantics exactly: zero-distance, canvas coordinate space
            let drag = DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                .updating($canvasDragTranslation) { value, state, _ in
                    state = value.translation
                    applyDragLive(translation: value.translation)
                }
                .onChanged { value in
                    applyDragLive(translation: value.translation)
                }
                .onEnded { _ in
                    dragStartPosition = nil
                }

            // Combine pinch + rotate simultaneously, and also allow drag
            let combined = SimultaneousGesture(SimultaneousGesture(pinch, rotate), drag).map { _ in () }
            let g = combined
            return AnyGesture(g)
        } else {
            // Global pinch for iOS 16-
            let pinch = MagnificationGesture()
                .updating($canvasMagnify) { value, state, _ in state = value }
                .onEnded { value in commitScaleDelta(value) }

            // Global rotate for iOS 16-
            let rotate = RotationGesture()
                .updating($canvasRotate) { value, state, _ in state = value }
                .onEnded { value in commitRotationDelta(value) }

            let drag = DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                .updating($canvasDragTranslation) { value, state, _ in
                    state = value.translation
                    applyDragLive(translation: value.translation)
                }
                .onChanged { value in
                    applyDragLive(translation: value.translation)
                }
                .onEnded { _ in
                    dragStartPosition = nil
                }

            let g = SimultaneousGesture(SimultaneousGesture(pinch, rotate), drag).map { _ in () }
            return AnyGesture(g)
        }
    }

    private func commitScaleDelta(_ scaleDelta: CGFloat) {
        guard scaleDelta.isFinite, scaleDelta > 0.001 else { return }
        if let id = state.selectedTextId,
           let i = state.textOverlays.firstIndex(where: { $0.id == id }) {
            let clamped = max(0.2, min(6.0, state.textOverlays[i].base.scale * scaleDelta))
            state.textOverlays[i].base.scale = clamped
            return
        }
        if let id = state.selectedMediaId,
           let i = state.mediaOverlays.firstIndex(where: { $0.id == id }) {
            let clamped = max(0.2, min(6.0, state.mediaOverlays[i].scale * scaleDelta))
            state.mediaOverlays[i].scale = clamped
            return
        }
    }

    private func commitRotationDelta(_ delta: Angle) {
        guard delta.radians.isFinite else { return }
        if let id = state.selectedTextId,
           let i = state.textOverlays.firstIndex(where: { $0.id == id }) {
            state.textOverlays[i].base.rotation += CGFloat(delta.radians)
            return
        }
        if let id = state.selectedMediaId,
           let i = state.mediaOverlays.firstIndex(where: { $0.id == id }) {
            state.mediaOverlays[i].rotation += CGFloat(delta.radians)
            return
        }
    }

    private func applyDragLive(translation: CGSize) {
        if let id = state.selectedTextId,
           let i = state.textOverlays.firstIndex(where: { $0.id == id }) {
            let start = dragStartPosition ?? state.textOverlays[i].base.position
            if dragStartPosition == nil { dragStartPosition = start }
            let newX = start.x + translation.width
            let newY = start.y + translation.height
            state.textOverlays[i].base.position = CGPoint(x: newX, y: newY)
            return
        }
        if let id = state.selectedMediaId,
           let i = state.mediaOverlays.firstIndex(where: { $0.id == id }) {
            let start = dragStartPosition ?? state.mediaOverlays[i].position
            if dragStartPosition == nil { dragStartPosition = start }
            let newX = start.x + translation.width
            let newY = start.y + translation.height
            state.mediaOverlays[i].position = CGPoint(x: newX, y: newY)
            return
        }
    }
}

// MARK: - Visibility helpers for overlays
private func isVisible(_ m: TimedMediaOverlay, at time: CMTime) -> Bool {
    guard time.isNumeric else { return false }
    let start = m.effectiveStart
    let end = m.effectiveStart + m.trimmedDuration
    return time >= start && time <= end
}

// MARK: - Modifier to apply transform gesture without intercepting taps/buttons
private struct SelectedTransformGestureModifier: ViewModifier {
    let isActive: Bool
    let gestureProvider: () -> AnyGesture<Void>
    func body(content: Content) -> some View {
        if isActive {
            content.simultaneousGesture(gestureProvider(), including: .gesture)
        } else {
            content
        }
    }
}


