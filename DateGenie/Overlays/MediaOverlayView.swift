import SwiftUI
import AVFoundation

struct MediaOverlayView: View {
    @Binding var model: TimedMediaOverlay
    let canvasSize: CGSize
    // Optional external transform deltas from a canvas-wide gesture layer
    var externalScaleDelta: CGFloat = 1
    var externalRotationDelta: Angle = .zero
    var externalAnchor: UnitPoint = .center
    var enableInternalTransformGesture: Bool = true
    // Allow reuse for non-selected render path while preserving identical sizing
    var showSelectionChips: Bool = true

    // Transient gesture states
    @GestureState private var drag: CGSize = .zero
    @GestureState private var magnify: CGFloat = 1
    @GestureState private var rotate: Angle = .zero
    @State private var transformAnchor: UnitPoint = .center
    @State private var didBeginDrag: Bool = false

    // Cached native media size and optional thumbnail for video
    @State private var nativeSize: CGSize = .zero
    @State private var videoThumb: UIImage? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            let base = fittedBaseSize()
            content
                .frame(width: base.width, height: base.height)
            if showSelectionChips {
                selectionRectWithChips(width: base.width, height: base.height)
            }
        }
        // Ensure transparent regions within the overlay's bounds are hittable for gestures
        .contentShape(Rectangle())
        .position(livePosition)
        .animation(nil, value: drag)
        .scaleEffect(safeScale(model.scale * magnify * externalScaleDelta), anchor: enableInternalTransformGesture ? transformAnchor : externalAnchor)
        .rotationEffect(safeAngle(Angle(radians: Double(model.rotation)) + rotate + externalRotationDelta), anchor: enableInternalTransformGesture ? transformAnchor : externalAnchor)
        .gesture(enableInternalTransformGesture ? dragGesture.simultaneously(with: anchoredTransformGesture) : nil, including: .gesture)
        .zIndex(Double(model.zIndex))
        .onAppear { probeNativeSizeIfNeeded() }
    }

    @ViewBuilder private var content: some View {
        switch model.kind {
        case .photo:
            if let img = UIImage(contentsOfFile: model.url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .allowsHitTesting(false)
            }
        case .video:
            if let ui = videoThumb {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .allowsHitTesting(false)
            } else {
                Rectangle().fill(Color.black.opacity(0.4)).allowsHitTesting(false)
            }
        }
    }

    private func selectionRectWithChips(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(Color.white, lineWidth: 1)
            .frame(width: width, height: height, alignment: .topLeading)
            .overlay(chip(system: "xmark") {
                NotificationCenter.default.post(name: Notification.Name("DeleteSelectedMediaOverlay"), object: model.id)
            }, alignment: .topLeading)
            .overlay(assetChipButton("text_duplicate") {
                NotificationCenter.default.post(name: Notification.Name("DuplicateSelectedMediaOverlay"), object: model.id)
            }
            .offset(x: -14, y: 14), alignment: .bottomLeading)
            .overlay(assetChipButton("text_unselect") {
                NotificationCenter.default.post(name: Notification.Name("UnselectMediaOverlay"), object: model.id)
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
        .offset(x: -14, y: -14)
    }

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
                withTransaction(.init(animation: nil)) { model.position = committed }
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

    private func fittedBaseSize() -> CGSize {
        // Determine the base content size (before model.scale) respecting aspect ratio
        let src = nativeSize == .zero ? CGSize(width: 400, height: 400) : nativeSize
        let maxW = canvasSize.width * 0.6
        let maxH = canvasSize.height * 0.6
        let fit = AVMakeRect(aspectRatio: src, insideRect: CGRect(x: 0, y: 0, width: maxW, height: maxH)).size
        return fit
    }

    private func probeNativeSizeIfNeeded() {
        if nativeSize == .zero {
            switch model.kind {
            case .photo:
                if let img = UIImage(contentsOfFile: model.url.path) {
                    nativeSize = img.size
                }
            case .video:
                let asset = AVURLAsset(url: model.url)
                if let track = asset.tracks(withMediaType: .video).first {
                    nativeSize = track.naturalSize.applying(track.preferredTransform).applying(CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)).applying(.identity).applying(.identity).applying(.identity).applying(.identity)
                    // Thumbnail (first frame)
                    let gen = AVAssetImageGenerator(asset: asset)
                    gen.appliesPreferredTrackTransform = true
                    if let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) {
                        videoThumb = UIImage(cgImage: cg)
                    }
                }
            }
        }
    }

    private func clamp(_ v: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat { Swift.min(Swift.max(v, min), max) }
    private func safeScale(_ s: CGFloat) -> CGFloat { s.isFinite && s > 0 ? s : 1 }
    private func safeAngle(_ a: Angle) -> Angle { a.radians.isFinite ? a : .zero }
}


