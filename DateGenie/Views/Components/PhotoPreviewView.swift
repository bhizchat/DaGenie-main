import SwiftUI
import Photos
import PencilKit
import StoreKit

struct PhotoPreviewView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage? = nil
    @State private var toast: ToastMessage? = nil
    @State private var showPaywall: Bool = false
    @StateObject private var sub = SubscriptionManager.shared
    @State private var pendingAction: PendingAction? = nil
    enum PendingAction { case save, share }
    // Inline overlays state
    @State private var overlayState = OverlayState()
    @State private var canvasRect: CGRect = .zero
    // Drawing tool removed
    @FocusState private var activeTextOverlayID: UUID?
    // If user taps add text before measurement, queue it
    @State private var pendingTextInsert: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if let image = image {
                    GeometryReader { g in
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        // Emit the aspect-fit canvas rect for overlays
                        Color.clear.preference(key: PreviewCanvasRectPreferenceKey.self,
                                               value: aspectFitRect(contentSize: image.size, in: g.frame(in: .local)))
                    }
                    .ignoresSafeArea()
                } else if url.scheme?.hasPrefix("http") == true {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty: ProgressView().tint(.white)
                        case .success(let img): img.resizable().scaledToFit()
                        default: Color.black
                        }
                    }
                } else {
                    ProgressView().tint(.white)
                }
            }

            // Top-left close
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image("icon_preview_close")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .padding(10)
                    }
                    Spacer()
                }
                .padding(.top, 24)
                .padding(.leading, 6)
                Spacer()
            }

            // Text overlays
            if image != nil, canvasRect.width > 1 && canvasRect.height > 1 {
                ForEach($overlayState.texts) { $item in
                    TextOverlayView(model: $item,
                                    isEditing: isEditing(item.id),
                                    onBeginEdit: {
                                        overlayState.mode = .textEdit(id: item.id)
                                        DispatchQueue.main.async { activeTextOverlayID = item.id }
                                    },
                                    onEndEdit: {
                                        overlayState.mode = .none
                                        DispatchQueue.main.async { activeTextOverlayID = nil }
                                    },
                                    activeTextId: $activeTextOverlayID,
                                    canvasSize: canvasRect.size)
                        .frame(width: canvasRect.width, height: canvasRect.height, alignment: .topLeading)
                        .position(x: canvasRect.midX, y: canvasRect.midY)
                        .zIndex(1)
                        .coordinateSpace(name: "canvas")
                }
            }

            // Right-side tools (Text / Draw + inlined color slider for draw)
            VStack(spacing: 18) {
                Button(action: addText) {
                    Image("icon_preview_text")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .padding(6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 12)
            .padding(.top, 28)

            // Inline editing now handled inside TextOverlayView; remove legacy bottom editor bar

            // Bottom bar with Download (left) + Share pill (right)
            if !isEditingActive() { // hide while actively editing a text overlay
                VStack {
                    Spacer()
                    HStack {
                         Button(action: saveToPhotos) {
                            ZStack {
                                Circle()
                                    .fill(brandRed)
                                    .frame(width: 56, height: 56)
                                Image("icon_preview_download")
                                    .renderingMode(.original)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                            }
                        }
                        Spacer()
                         Button(action: share) {
                            HStack(spacing: 10) {
                                Text("Share")
                                    .font(.vt323(26))
                                    .foregroundColor(.white)
                                Image("icon_preview_share")
                                    .renderingMode(.original)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(brandRed)
                            .cornerRadius(100)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(Color.black.opacity(1.0).ignoresSafeArea(edges: .bottom))
                }
            }
        }
        .toast(message: $toast)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear(perform: loadImage)
        .sheet(isPresented: $showPaywall, onDismiss: {
            print("[PhotoPreviewView] paywall dismissed; isSubscribed=\(sub.isSubscribed)")
            if !sub.isSubscribed {
                print("[PhotoPreviewView] setting requiresSubscriptionForGeneration=true after dismiss")
                Task { await SubscriptionGate.setRequireForGenerationTrue() }
            }
        }) {
            PaywallView()
                .onAppear { print("[PhotoPreviewView] presenting PaywallView (pending=\(String(describing: pendingAction)))") }
        }
        .onChange(of: sub.isSubscribed) { ok in
            guard ok, showPaywall else { return }
            switch pendingAction {
            case .save: saveToPhotos()
            case .share: share()
            case .none: break
            }
            pendingAction = nil
            showPaywall = false
        }
        .onAppear {
            // Fallback: if measurement is delayed, compute a best-effort canvas from screen bounds
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if canvasRect == .zero, let img = image {
                    let screen = UIScreen.main.bounds
                    let computed = aspectFitRect(contentSize: img.size, in: screen)
                    print("[PhotoPreviewView] fallback canvasRect computed ->", computed)
                    canvasRect = computed
                }
            }
        }
        .onPreferenceChange(PreviewCanvasRectPreferenceKey.self) { rect in
            if !rectApproximatelyEqual(canvasRect, rect, epsilon: 0.5) {
                DispatchQueue.main.async {
                    print("[PhotoPreviewView] canvasRect updated ->", rect)
                    canvasRect = rect
                    if canvasRect.width > 1 && canvasRect.height > 1, pendingTextInsert {
                        pendingTextInsert = false
                        print("[PhotoPreviewView] completing pending text insert after measurement")
                        createAndFocusCenteredText()
                    }
                    // Recenter any text that may have been created with an invalid/zero position
                    recenterTextsIfNeeded()
                }
            }
        }
    }

    private func loadImage() {
        guard image == nil, url.scheme?.hasPrefix("http") != true else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                DispatchQueue.main.async { self.image = img }
            }
        }
    }

    private func saveToPhotos() {
        guard sub.isSubscribed else { pendingAction = .save; showPaywall = true; print("[PhotoPreviewView] gating save → showPaywall=true"); return }
        // If overlays exist, merge first
        if let img = image, hasOverlays {
            let merged = OverlayExporter.renderMergedImage(baseImage: img,
                                                          canvasRect: canvasRect,
                                                          drawing: overlayState.drawing,
                                                          texts: overlayState.texts)
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dg_merged_\(UUID().uuidString).jpg")
            if let data = merged.jpegData(compressionQuality: 0.95) { try? data.write(to: tempURL) }
            return saveFileToPhotos(tempURL)
        }
        saveFileToPhotos(url)
    }

    private func saveFileToPhotos(_ fileURL: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    toast = ToastMessage(text: "Permission needed to save. Enable Photos access in Settings.", style: .error)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            }, completionHandler: { success, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("[PhotoPreviewView] saveToPhotos error: \(error)")
                        toast = ToastMessage(text: "Couldn't save to Photos. Try again.", style: .error)
                    } else {
                        toast = ToastMessage(text: "Saved to Photos", style: .success)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
                }
            })
        }
    }

    private func share() {
        guard sub.isSubscribed else { pendingAction = .share; showPaywall = true; print("[PhotoPreviewView] gating share → showPaywall=true"); return }
        let itemURL: URL = {
            if let img = image, hasOverlays {
                let merged = OverlayExporter.renderMergedImage(baseImage: img,
                                                              canvasRect: canvasRect,
                                                              drawing: overlayState.drawing,
                                                              texts: overlayState.texts)
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dg_merged_\(UUID().uuidString).jpg")
                if let data = merged.jpegData(compressionQuality: 0.95) { try? data.write(to: tempURL) }
                return tempURL
            }
            return url
        }()
        let av = UIActivityViewController(activityItems: [itemURL], applicationActivities: nil)
        UIApplication.shared.topMostViewController()?.present(av, animated: true)
    }

    private func addText() {
        guard image != nil else { return }
        print("[PhotoPreviewView] T tapped; canvasRect=", canvasRect)
        // If not yet measured, queue up the action
        guard canvasRect.width > 1 && canvasRect.height > 1 else { pendingTextInsert = true; print("[PhotoPreviewView] queued text insert until measurement"); return }
        createAndFocusCenteredText()
        recenterTextsIfNeeded()
    }

    // Drawing tool removed

    private var hasOverlays: Bool { !overlayState.texts.isEmpty || !overlayState.drawing.bounds.isEmpty }

    private func isEditing(_ id: UUID) -> Bool { if case let .textEdit(editId) = overlayState.mode { return editId == id } ; return false }
    private func isEditingActive() -> Bool { if case .textEdit = overlayState.mode { return true } ; return false }

    private func cycleStyle(for idx: Int) {
        let next: TextStyle = {
            switch overlayState.texts[idx].style {
            case .small: return .largeCenter
            case .largeCenter: return .largeBackground
            case .largeBackground: return .small
            }
        }()
        overlayState.texts[idx].style = next
    }

    // Legacy merge kept for reference; replaced by OverlayExporter

    private func draw(text t: TextOverlay, in cg: CGContext, canvas: CGRect, exportScale: CGFloat) {
        let attrs = textAttributes(for: t)
        let ns = NSString(string: t.string.isEmpty ? " " : t.string)
        let bounds = ns.size(withAttributes: attrs)
        cg.saveGState()
        let tx = (t.position.x) * exportScale
        let ty = (t.position.y) * exportScale
        cg.translateBy(x: tx, y: ty)
        cg.rotate(by: t.rotation)
        // Scale text to match on-screen size: include exportScale
        cg.scaleBy(x: t.scale * exportScale, y: t.scale * exportScale)
        cg.translateBy(x: -bounds.width/2, y: -bounds.height/2)
        ns.draw(at: .zero, withAttributes: attrs)
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
        return [ .font: font, .foregroundColor: uiColor, .shadow: shadow, .strokeColor: UIColor.black, .strokeWidth: -2.0 ]
    }

    private var brandRed: Color { Color(red: 242/255, green: 109/255, blue: 100/255) }
}

// MARK: - Utilities
private func rectApproximatelyEqual(_ a: CGRect, _ b: CGRect, epsilon: CGFloat) -> Bool {
    abs(a.minX - b.minX) <= epsilon &&
    abs(a.minY - b.minY) <= epsilon &&
    abs(a.width - b.width) <= epsilon &&
    abs(a.height - b.height) <= epsilon
}

private extension PhotoPreviewView {
    func createAndFocusCenteredText() {
        print("[PhotoPreviewView] creating centered text overlay")
        let center = CGPoint(x: canvasRect.width/2, y: canvasRect.height/2)
        var item = TextOverlay(string: "", position: center, zIndex: (overlayState.texts.map { $0.zIndex }.max() ?? 0) + 1)
        item.color = RGBAColor(overlayState.lastTextColor)
        overlayState.texts.append(item)
        overlayState.mode = .textEdit(id: item.id)
        DispatchQueue.main.async {
            activeTextOverlayID = item.id
            print("[PhotoPreviewView] requested focus for text id=", item.id)
        }
    }

    func recenterTextsIfNeeded() {
        guard canvasRect.width > 1 && canvasRect.height > 1 else { return }
        var changed = false
        for idx in overlayState.texts.indices {
            let p = overlayState.texts[idx].position
            if !p.x.isFinite || !p.y.isFinite || (abs(p.x) < 0.001 && abs(p.y) < 0.001) {
                overlayState.texts[idx].position = CGPoint(x: canvasRect.width/2, y: canvasRect.height/2)
                changed = true
            }
        }
        if changed { print("[PhotoPreviewView] recentered text overlays with invalid positions") }
    }
}

// MARK: - Canvas rect preference calculator for preview
private struct PreviewCalcCanvasRect: View {
    let size: CGSize
    var body: some View {
        GeometryReader { g in
            Color.clear.preference(key: PreviewCanvasRectPreferenceKey.self,
                                   value: aspectFitRect(contentSize: size, in: g.frame(in: .local)))
        }
    }
}

private struct PreviewCanvasRectPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}


