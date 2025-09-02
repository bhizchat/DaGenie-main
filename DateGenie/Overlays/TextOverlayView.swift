import SwiftUI
import UIKit
import CoreText

struct TextOverlayView: View {
    @Binding var model: TextOverlay
    var isEditing: Bool
    var onBeginEdit: () -> Void
    var onEndEdit: () -> Void
    var activeTextId: FocusState<UUID?>.Binding
    let canvasSize: CGSize

    @GestureState private var drag: CGSize = .zero
    @State private var didBeginDrag: Bool = false
    // Transient transform state (per Apple docs) and dynamic anchor
    @GestureState private var magnify: CGFloat = 1
    @GestureState private var rotate: Angle = .zero
    @State private var transformAnchor: UnitPoint = .center
    // Live measured glyph size (unscaled) used to size the selection rect and anchor chips
    @State private var measuredTextSize: CGSize = .zero

    var body: some View {
        Group {
            if isEditing {
                // Editable text field
                TextField(" ", text: $model.string)
                    .focused(activeTextId, equals: model.id)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit { onEndEdit() }
                    .font(fontForStyle())
                    .foregroundColor(model.color.color)
                    .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(6)
                    .frame(minWidth: 60, minHeight: 38)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.sentences)
                    .task(id: isEditing) { if isEditing { activeTextId.wrappedValue = model.id } }
            } else {
                // Selected overlay: content + measured selection rect with corner-anchored chips
                ZStack(alignment: .topLeading) {
                    let size = rectSize()
                    content
                        .frame(width: size.width, height: size.height, alignment: .center)
                    selectionRectWithChips
                }
                // Double-tap to edit should win vs background single-tap, but not override chip buttons
                .highPriorityGesture(
                    TapGesture(count: 2).onEnded { onBeginEdit() },
                    including: .gesture
                )
                // Single-tap on background (not chips): close typing or unselect
                .gesture(
                    TapGesture(count: 1).onEnded {
                        NotificationCenter.default.post(name: Notification.Name("CanvasTapOnSelectedText"), object: nil)
                    },
                    including: .gesture
                )
            }
        }
        .position(livePosition)
        .animation(nil, value: drag)
        .scaleEffect(safeScale(model.scale * magnify), anchor: transformAnchor)
        .rotationEffect(safeAngle(Angle(radians: Double(model.rotation)) + rotate), anchor: transformAnchor)
        .gesture(isEditing ? nil : dragGesture.simultaneously(with: anchoredTransformGesture), including: .gesture)
        .zIndex(Double(model.zIndex))
        .onAppear { recomputeMeasuredSize() }
        .onChange(of: model.string) { _ in recomputeMeasuredSize() }
        .onChange(of: model.style) { _ in recomputeMeasuredSize() }
    }

    @ViewBuilder private var content: some View {
        let display = model.string.isEmpty ? "Enter text" : model.string
        let text = Text(display)
            .font(fontForStyle())
            .foregroundColor(model.color.color)
            .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)

        switch model.style {
        case .small:
            text
        case .largeCenter:
            text.multilineTextAlignment(.center)
        case .largeBackground:
            text
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.5).blur(radius: 0.5))
                .cornerRadius(6)
        }
    }

    // MARK: - Measured selection rect with chips anchored at the four corners
    private var selectionRectWithChips: some View {
        let size = rectSize()
        let rectW = size.width
        let rectH = size.height

        return RoundedRectangle(cornerRadius: 4)
            .stroke(Color.white, lineWidth: 1)
            .frame(width: rectW, height: rectH, alignment: .topLeading)
            // Corner chips anchored using overlay(alignment:)
            .overlay(chip(system: "xmark") {
                NotificationCenter.default.post(name: Notification.Name("DeleteSelectedTextOverlay"), object: model.id)
            }, alignment: .topLeading)
            .overlay(chip(system: "pencil") {
                NotificationCenter.default.post(name: Notification.Name("OpenTypingDockForSelectedText"), object: model.id)
            }, alignment: .topTrailing)
            // Bottom chips now use custom asset icons
            .overlay(assetChipButton("text_duplicate") {
                NotificationCenter.default.post(name: Notification.Name("DuplicateSelectedTextOverlay"), object: model.id)
            }
            .offset(x: -14, y: 14), alignment: .bottomLeading)
            .overlay(assetChipButton("text_unselect") {
                NotificationCenter.default.post(name: Notification.Name("UnselectTextOverlay"), object: model.id)
            }
            .offset(x: 14, y: 14), alignment: .bottomTrailing)
    }

    private func chip(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color.black.opacity(0.7))
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: system).foregroundColor(.white).font(.system(size: 12, weight: .bold)))
        }
        .buttonStyle(.plain)
        // Nudge outward so chips sit just outside the stroked rect
        .offset(x: (system == "xmark" || system == "doc.on.doc") ? -14 : 14,
                y: (system == "xmark" || system == "pencil") ? -14 : 14)
    }

    // Asset-based chip button (for non-SF-symbol icons)
    private func assetChipButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color.black.opacity(0.7))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(name)
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundColor(.white)
                )
        }
        .buttonStyle(.plain)
    }

    private func fontForStyle() -> Font {
        switch model.style {
        case .small: return .system(size: 24, weight: .regular)
        case .largeCenter, .largeBackground: return .system(size: 42, weight: .bold)
        }
    }

    private func uiFontForStyle() -> UIFont {
        switch model.style {
        case .small: return .systemFont(ofSize: 24, weight: .regular)
        case .largeCenter, .largeBackground: return .systemFont(ofSize: 42, weight: .bold)
        }
    }

    // Compute tight single-line text bounds using Core Text
    private func recomputeMeasuredSize() {
        let s = model.string.isEmpty ? "Enter text" : model.string
        let font = uiFontForStyle()
        let attr = NSAttributedString(string: s, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attr as CFAttributedString)
        let img = CTLineGetImageBounds(line, nil)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let advW = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let w = (img.isNull || !img.width.isFinite) ? advW : img.width
        let h = ascent + descent
        measuredTextSize = CGSize(width: ceil(max(1, w)), height: ceil(max(1, h)))
    }

    // Unified rectangle size used for both centered content and stroked rect
    private func rectSize() -> CGSize {
        // Extra visual breathing room so the rect isn't too tight
        let extraInsetW: CGFloat = 20
        let extraInsetH: CGFloat = 12
        let paddingW: CGFloat = ((model.style == .largeBackground) ? 16 : 0) + extraInsetW
        let paddingH: CGFloat = ((model.style == .largeBackground) ? 8  : 0) + extraInsetH
        let rectW = max(1, measuredTextSize.width + paddingW)
        let rectH = max(1, measuredTextSize.height + paddingH)
        return CGSize(width: rectW, height: rectH)
    }

    private var livePosition: CGPoint {
        CGPoint(x: model.position.x + drag.width,
                y: model.position.y + drag.height)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
            .updating($drag) { value, state, _ in
                state = value.translation
                if !didBeginDrag {
                    didBeginDrag = true
                    withTransaction(.init(animation: nil)) { model.zIndex += 1 }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .onEnded { value in
                didBeginDrag = false
                let dx = value.translation.width.isFinite ? value.translation.width : 0
                let dy = value.translation.height.isFinite ? value.translation.height : 0
                let committed = CGPoint(x: model.position.x + dx,
                                        y: model.position.y + dy)
                let clamped = CGPoint(
                    x: Swift.min(Swift.max(committed.x, 0), canvasSize.width),
                    y: Swift.min(Swift.max(committed.y, 0), canvasSize.height)
                )
                withTransaction(.init(animation: nil)) { model.position = clamped }
            }
    }

    private var anchoredTransformGesture: AnyGesture<Void> {
        if #available(iOS 17, *) {
            let g = SimultaneousGesture(
                MagnifyGesture(minimumScaleDelta: 0.005)
                    .updating($magnify) { value, state, _ in
                        state = value.magnification
                        transformAnchor = value.startAnchor
                    }
                    .onEnded { value in
                        let s = value.magnification
                        if s.isFinite && s > 0.001 {
                            model.scale = clamp(model.scale * s, min: 0.2, max: 6.0)
                        }
                    },
                RotationGesture()
                    .updating($rotate) { value, state, _ in
                        // Apply a small threshold to reduce jitter (~0.25°)
                        let minRad: Double = 0.0043633231
                        state = abs(value.radians) < minRad ? .zero : value
                    }
                    .onEnded { value in
                        if value.radians.isFinite { model.rotation += CGFloat(value.radians) }
                    }
            ).map { _ in () }
            return AnyGesture(g)
        } else {
            let g = SimultaneousGesture(
                MagnificationGesture()
                    .updating($magnify) { value, state, _ in state = value }
                    .onEnded { value in
                        if value.isFinite && value > 0.001 {
                            model.scale = clamp(model.scale * value, min: 0.2, max: 6.0)
                        }
                    },
                RotationGesture()
                    .updating($rotate) { value, state, _ in state = value }
                    .onEnded { value in
                        if value.radians.isFinite { model.rotation += CGFloat(value.radians) }
                    }
            ).map { _ in () }
            return AnyGesture(g)
        }
    }

    private func clamp(_ v: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat { Swift.min(Swift.max(v, min), max) }
    private func safeScale(_ s: CGFloat) -> CGFloat { s.isFinite && s > 0 ? s : 1 }
    private func safeAngle(_ a: Angle) -> Angle { a.radians.isFinite ? a : .zero }
}


