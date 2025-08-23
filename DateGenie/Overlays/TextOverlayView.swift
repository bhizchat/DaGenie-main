import SwiftUI

struct TextOverlayView: View {
    @Binding var model: TextOverlay
    var isEditing: Bool
    var onBeginEdit: () -> Void
    var onEndEdit: () -> Void
    var activeTextId: FocusState<UUID?>.Binding
    let canvasSize: CGSize

    @GestureState private var drag: CGSize = .zero
    @State private var didBeginDrag: Bool = false
    @State private var currentScale: CGFloat = 1
    @State private var currentRotation: Angle = .zero

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
                content
                    .onTapGesture(count: 2, perform: onBeginEdit)
            }
        }
        .position(livePosition)
        .animation(nil, value: drag)
        .scaleEffect(safeScale(model.scale * currentScale))
        .rotationEffect(safeAngle(Angle(radians: Double(model.rotation)) + currentRotation))
        .gesture(isEditing ? nil : dragGesture.simultaneously(with: pinchAndRotate))
        .zIndex(Double(model.zIndex))
    }

    @ViewBuilder private var content: some View {
        let text = Text(model.string)
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

    private func fontForStyle() -> Font {
        switch model.style {
        case .small: return .system(size: 24, weight: .regular)
        case .largeCenter, .largeBackground: return .system(size: 42, weight: .bold)
        }
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

    private var pinchAndRotate: some Gesture {
        SimultaneousGesture(
            MagnificationGesture().onChanged { scale in currentScale = scale }
                .onEnded { scale in
                    if scale.isFinite && scale > 0.001 {
                        model.scale = clamp(model.scale * scale, min: 0.2, max: 6.0)
                    }
                    currentScale = 1
                },
            RotationGesture().onChanged { angle in currentRotation = angle }
                .onEnded { angle in
                    if angle.radians.isFinite { model.rotation += CGFloat(angle.radians) }
                    currentRotation = .zero
                }
        )
    }

    private func clamp(_ v: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat { Swift.min(Swift.max(v, min), max) }
    private func safeScale(_ s: CGFloat) -> CGFloat { s.isFinite && s > 0 ? s : 1 }
    private func safeAngle(_ a: Angle) -> Angle { a.radians.isFinite ? a : .zero }
}


