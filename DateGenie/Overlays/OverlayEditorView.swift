import SwiftUI
import PencilKit

struct OverlayEditorView: View {
    let baseImage: UIImage
    let onCancel: () -> Void
    let onDone: (URL) -> Void

    @State private var state = OverlayState()
    // Drawing tool removed

    // Canvas rect used for placement + export mapping
    @State private var canvasRect: CGRect = .zero
    // Global bounds of the editor root (used to convert keyboard frame into local coords)
    @State private var rootGlobalBounds: CGRect = .zero
    // How much of the keyboard overlaps the canvas (in canvas coordinate space)
    @State private var keyboardOverlapInCanvas: CGFloat = 0
    @State private var isCaptionEditing: Bool = false
    @FocusState private var captionFocused: Bool
    @FocusState private var activeTextOverlayID: UUID?
    // If user taps T before layout measured, queue the action and complete after measurement
    @State private var pendingTextInsert: Bool = false
    @State private var pendingCaptionFocus: Bool = false

    var body: some View {
        ZStack {
            // Track root bounds for keyboard frame conversion
            GeometryReader { proxy in
                Color.clear.preference(key: RootBoundsPreferenceKey.self, value: proxy.frame(in: .global))
            }
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()
                    // Media
                    GeometryReader { g in
                        ZStack {
                            Image(uiImage: baseImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        Color.clear.preference(key: CanvasRectPreferenceKey.self,
                                               value: aspectFitRect(contentSize: baseImage.size, in: g.frame(in: .local)))
                    }

                    // Drawing tool removed

                    // Text overlays
                    if canvasRect.width > 1 && canvasRect.height > 1 {
                        ForEach($state.texts) { $item in
                            TextOverlayView(model: $item,
                                            isEditing: isEditing(item.id),
                                            onBeginEdit: {
                                                state.mode = .textEdit(id: item.id)
                                                DispatchQueue.main.async { activeTextOverlayID = item.id }
                                            },
                                            onEndEdit: {
                                                // Exit text edit mode when submit tapped
                                                state.mode = .none
                                                activeTextOverlayID = nil
                                            },
                                            activeTextId: $activeTextOverlayID,
                                            canvasSize: canvasRect.size)
                                .frame(width: canvasRect.width, height: canvasRect.height, alignment: .topLeading)
                                .position(x: canvasRect.minX, y: canvasRect.minY)
                                .zIndex(1)
                        }
                    }
                }
            }

            // Tap-catcher: dismiss caption editing when tapping outside
            if isCaptionEditing {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        captionFocused = false
                        isCaptionEditing = false
                    }
            }

            // Tooling
            VStack {
                HStack {
                    Button(action: onCancel) { Image("icon_preview_close").resizable().scaledToFit().frame(width: 28, height: 28).padding(10) }
                    Spacer()
                    HStack(spacing: 16) {
                        Button(action: { enterCaption() }) { Image("icon_preview_text").resizable().scaledToFit().frame(width: 28, height: 28).padding(6) }
                        Button(action: { enterText() }) { Image("icon_preview_text").resizable().scaledToFit().frame(width: 28, height: 28).padding(6) }
                    }
                }
                .padding(.top, 16).padding(.horizontal, 12)
                Spacer()
                // Drawing color slider removed
            }

            // Bottom bar actions
            VStack {
                Spacer()
                if (canvasRect.width > 1 && canvasRect.height > 1) && (state.caption.isVisible || isCaptionEditing) {
                    CaptionBarView(committedText: $state.caption.text,
                                   verticalNormalized: $state.caption.verticalOffsetNormalized,
                                   isEditing: $isCaptionEditing,
                                   focus: $captionFocused,
                                   canvasRect: canvasRect,
                                   onTapToEdit: { isCaptionEditing = true },
                                   onDone: { finishCaptionEditing() })
                        .frame(width: canvasRect.width, height: canvasRect.height, alignment: .topLeading)
                        .position(x: canvasRect.midX, y: canvasRect.midY)
                        .zIndex(1000)
                }
                if !isCaptionEditing && !isEditingActive() {
                    HStack {
                        Button(action: { onDone(mergeAndExport()) }) {
                            HStack(spacing: 10) {
                                Text("Save").font(.vt323(24)).foregroundColor(.white)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Color(red: 242/255, green: 109/255, blue: 100/255))
                            .cornerRadius(100)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        // Let keyboard affect layout by default; individual layers can choose to ignore
        .onAppear {
            // Fallback measurement in case preference never fires quickly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if canvasRect == .zero {
                    let screen = UIScreen.main.bounds
                    let computed = aspectFitRect(contentSize: baseImage.size, in: screen)
                    print("[OverlayEditorView] fallback canvasRect computed ->", computed)
                    canvasRect = computed
                }
            }
        }
        .onPreferenceChange(CanvasRectPreferenceKey.self) { rect in
            // Defer and ignore tiny rounding oscillations to avoid layout-update loops
            if !rectApproximatelyEqual(canvasRect, rect, epsilon: 0.5) {
                DispatchQueue.main.async {
                    print("[OverlayEditorView] canvasRect updated ->", rect)
                    canvasRect = rect
                    // Complete any queued actions that require a valid canvas size
                    if canvasRect.width > 1 && canvasRect.height > 1 {
                        if pendingTextInsert {
                            pendingTextInsert = false
                            print("[OverlayEditorView] completing pending text insert after measurement")
                            createAndFocusCenteredText()
                        }
                        // Fix up invalid positions created when canvas was zero
                        recenterTextsIfNeeded()
                        if pendingCaptionFocus && isCaptionEditing {
                            pendingCaptionFocus = false
                            captionFocused = true
                        }
                    }
                }
            }
        }
        // Track the global bounds of this editor to convert keyboard frames into local space
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: RootBoundsPreferenceKey.self, value: proxy.frame(in: .global))
            }
        )
        .onPreferenceChange(RootBoundsPreferenceKey.self) { bounds in
            // Defer and guard against jitter
            if !rectApproximatelyEqual(rootGlobalBounds, bounds, epsilon: 0.5) {
                DispatchQueue.main.async { rootGlobalBounds = bounds }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func isEditing(_ id: UUID) -> Bool { if case let .textEdit(editId) = state.mode { return editId == id } ; return false }
    private func isEditingActive() -> Bool { if case .textEdit = state.mode { return true } ; return false }

    private func enterText() {
        guard canvasRect.width > 1 && canvasRect.height > 1 else {
            pendingTextInsert = true
            return
        }
        createAndFocusCenteredText()
        recenterTextsIfNeeded()
    }

    private func enterCaption() {
        if !state.caption.isVisible { state.caption.isVisible = true }
        isCaptionEditing = true
        if canvasRect.width > 1 && canvasRect.height > 1 {
            DispatchQueue.main.async { captionFocused = true }
        } else {
            pendingCaptionFocus = true
        }
    }

    private func finishCaptionEditing() {
        DispatchQueue.main.async {
            captionFocused = false
            isCaptionEditing = false
            if state.caption.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.caption.isVisible = false
            }
        }
    }

    // Drawing tool removed

    // Export a merged image at photo pixel size
    private func mergeAndExport() -> URL {
        let url = OverlayExporter.exportMergedImage(baseImage: baseImage,
                                                    canvasRect: canvasRect,
                                                    drawing: state.drawing,
                                                    texts: state.texts) ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dg_overlay_\(UUID().uuidString).jpg")
        return url
    }

    private func draw(text t: TextOverlay, in cg: CGContext, canvas: CGRect, exportScale: CGFloat) {
        let attrs = textAttributes(for: t)
        let ns = NSString(string: t.string.isEmpty ? " " : t.string)
        let bounds = ns.size(withAttributes: attrs)
        cg.saveGState()
        // Transform order: to pixel space, translate to position, rotate, scale, anchor to center
        let tx = (t.position.x) * exportScale
        let ty = (t.position.y) * exportScale
        cg.translateBy(x: tx, y: ty)
        cg.rotate(by: t.rotation)
        // Scale text to pixel space so exported size matches on-screen
        cg.scaleBy(x: t.scale * exportScale, y: t.scale * exportScale)
        cg.translateBy(x: -bounds.width/2, y: -bounds.height/2)
        ns.draw(at: .zero, withAttributes: attrs)
        if t.style == .largeBackground {
            // optional: draw BG first—skipped for brevity
        }
        cg.restoreGState()
    }

    private func textAttributes(for t: TextOverlay) -> [NSAttributedString.Key: Any] {
        let uiColor = t.color.uiColor
        let font: UIFont = {
            switch t.style {
            case .small: return .systemFont(ofSize: 24, weight: .regular)
            case .largeCenter, .largeBackground: return .boldSystemFont(ofSize: 42)
            }
        }()
        let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.8); shadow.shadowOffset = .init(width: 0, height: 1); shadow.shadowBlurRadius = 3
        return [
            .font: font,
            .foregroundColor: uiColor,
            .shadow: shadow,
            .strokeColor: UIColor.black,
            .strokeWidth: -2.0
        ]
    }

    // MARK: - Caption export
    private func draw(caption cap: CaptionModel, in cg: CGContext, canvas: CGRect, exportScale: CGFloat, imageSizePx: CGSize) {
        let uiTextColor = cap.textColor.uiColor
        let font = UIFont.systemFont(ofSize: cap.fontSize * exportScale, weight: .semibold)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: uiTextColor,
            .paragraphStyle: paragraph
        ]

        let ns = NSString(string: cap.text)
        let horizontalPaddingPx: CGFloat = 32 * exportScale
        let verticalPaddingPx: CGFloat = 12 * exportScale
        let availableWidth = imageSizePx.width - (horizontalPaddingPx * 2)

        var textBounds = ns.boundingRect(with: CGSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        // Limit to ~2 lines visually by capping height to 2.4x line height
        let lineHeight = font.lineHeight
        let maxHeight = lineHeight * 2.4
        if textBounds.height > maxHeight { textBounds.size.height = maxHeight }

        let vn = cap.verticalOffsetNormalized.isFinite ? max(0, min(1, cap.verticalOffsetNormalized)) : 0.8
        let yCanvas = canvas.minY + vn * canvas.height
        let yPx = yCanvas * exportScale
        let barHeight = textBounds.height + (verticalPaddingPx * 2)
        let barTop = max(0, yPx - barHeight / 2)
        let barRect = CGRect(x: 0, y: min(barTop, imageSizePx.height - barHeight), width: imageSizePx.width, height: barHeight)

        // Background bar
        cg.saveGState()
        let radius: CGFloat = 8 * exportScale
        let path = UIBezierPath(roundedRect: barRect, cornerRadius: radius)
        cg.setFillColor(cap.backgroundColor.uiColor.cgColor)
        cg.addPath(path.cgPath)
        cg.fillPath()
        cg.restoreGState()

        // Draw text centered in the bar
        let textRect = CGRect(x: horizontalPaddingPx,
                              y: barRect.minY + verticalPaddingPx,
                              width: availableWidth,
                              height: textBounds.height)
        ns.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
    }
}

// MARK: - Utilities
private func rectApproximatelyEqual(_ a: CGRect, _ b: CGRect, epsilon: CGFloat) -> Bool {
    abs(a.minX - b.minX) <= epsilon &&
    abs(a.minY - b.minY) <= epsilon &&
    abs(a.width - b.width) <= epsilon &&
    abs(a.height - b.height) <= epsilon
}

private extension OverlayEditorView {
    func createAndFocusCenteredText() {
        print("[OverlayEditorView] creating centered text overlay")
        let center = CGPoint(x: canvasRect.midX - canvasRect.minX, y: canvasRect.midY - canvasRect.minY)
        var item = TextOverlay(string: "", position: center, zIndex: (state.texts.map { $0.zIndex }.max() ?? 0) + 1)
        item.color = RGBAColor(state.lastTextColor)
        state.texts.append(item)
        state.mode = .textEdit(id: item.id)
        DispatchQueue.main.async {
            activeTextOverlayID = item.id
            print("[OverlayEditorView] requested focus for text id=", item.id)
        }
    }
    func recenterTextsIfNeeded() {
        guard canvasRect.width > 1 && canvasRect.height > 1 else { return }
        var changed = false
        for idx in state.texts.indices {
            let p = state.texts[idx].position
            if !p.x.isFinite || !p.y.isFinite || (abs(p.x) < 0.001 && abs(p.y) < 0.001) {
                state.texts[idx].position = CGPoint(x: canvasRect.width/2, y: canvasRect.height/2)
                changed = true
            }
        }
        if changed { print("[OverlayEditorView] recentered text overlays with invalid positions") }
    }
}

// MARK: - Canvas rect preference calculator
private struct CalcCanvasRect: View {
    let size: CGSize
    var body: some View {
        GeometryReader { g in
            Color.clear.preference(key: CanvasRectPreferenceKey.self,
                                   value: aspectFitRect(contentSize: size, in: g.frame(in: .local)))
        }
    }
}

private struct CanvasRectPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

// Global bounds preference for the editor root
private struct RootBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}


