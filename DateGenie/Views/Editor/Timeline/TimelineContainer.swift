import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

struct TimelineContainer: View {
    @ObservedObject var state: EditorState
    // Optional action for the \"Add ending\" pill
    let onAddEnding: (() -> Void)? = nil
    // Optional actions for Audio/Text quick-add buttons
    let onAddAudio: (() -> Void)? = nil
    let onAddText: (() -> Void)? = nil

    // View-local scroll state
    @State private var contentOffsetX: CGFloat = 0
    @GestureState private var dragDX: CGFloat = 0
    @GestureState private var pinchScale: CGFloat = 1.0
    // Timeline dimensions
    private let stripHeight: CGFloat = 72       // filmstrip height
    private let rulerHeight: CGFloat = 32       // header/ruler height above filmstrip
    private let spacingAboveStrip: CGFloat = 8  // gap between ruler and filmstrip
    private let extraPlayheadExtension: CGFloat = 80 // extend playhead/HUD upward

    // Config
    private let minPPS: CGFloat = 20
    private let maxPPS: CGFloat = 300

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Stack ruler above filmstrip with a small gap
                VStack(spacing: spacingAboveStrip) {
                    // Ruler overlay (seconds ticks) in header
                    rulerOverlay(width: geo.size.width, center: geo.size.width / 2)
                        .frame(height: rulerHeight)
                        .offset(y: -105) // raise ruler vertically by ~105pt total

                    // Filmstrip scroll area (multi-clip)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            // Leading inset so 0s aligns flush with the fixed playhead line
                            let leadingInset = max(0, (geo.size.width / 2) - 2) // nudge left ~2pt so thumbnails touch playhead
                            Color.clear.frame(width: leadingInset, height: stripHeight)
                            // Render each clip as a contiguous strip of its thumbnails
                            ForEach(Array(state.clips.enumerated()), id: \.element.id) { _, clip in
                                let clipWidth = CGFloat(max(0, CMTimeGetSeconds(clip.duration))) * state.pixelsPerSecond
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Color.gray.opacity(0.15))
                                        .frame(width: clipWidth, height: stripHeight)
                                    HStack(spacing: 0) {
                                        let count = max(1, clip.thumbnails.count)
                                        ForEach(0..<count, id: \.self) { i in
                                            let img = i < clip.thumbnails.count ? clip.thumbnails[i] : UIImage()
                                            Image(uiImage: img)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: max(24, state.pixelsPerSecond), height: stripHeight)
                                                .clipped()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: stripHeight)
                    .contentOffset(x: contentOffsetX + dragDX) // via extension below
                    .gesture(dragGesture(geo: geo))
                    // Move filmstrip into the top lane, flush with the playhead line
                    .offset(y: -((stripHeight + spacingAboveStrip + rulerHeight)/2) - 10)
                    .zIndex(0)

                }

                // Centered playhead line spanning ruler + gap + strip
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: stripHeight + spacingAboveStrip + rulerHeight + extraPlayheadExtension)

                // Timecode HUD during scrubbing
                if state.isScrubbing {
                    VStack(spacing: 4) {
                        Text(timeString(state.currentTime))
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(6)
                    }
                    .offset(y: -((stripHeight + spacingAboveStrip + rulerHeight + extraPlayheadExtension)/2) - 20)
                    .transition(.opacity)
                }
            }
            // Fixed left time counter (mm:ss / mm:ss) anchored to top-left of the timeline container
            .overlay(alignment: .topLeading) {
                Text("\(mmss(seconds(state.currentTime))) / \(mmss(seconds(state.duration)))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.leading, 12)
                    .padding(.top, 6)
            }
            // "+ Add ending" pill positioned immediately after the end of the thumbnails
            .overlay(alignment: .center) {
                // Width tied to ~2 seconds of timeline so it ends around ~2s when empty
                let pillWidth: CGFloat = max(110, state.pixelsPerSecond * 2 - 8)
                let totalSeconds = max(0, CMTimeGetSeconds(state.totalDuration))
                // Align to end of filmstrip accounting for the leading inset (center-playhead)
                let leadingInset = max(0, (geo.size.width / 2) - 2)
                let pillX = leadingInset + (state.pixelsPerSecond * CGFloat(totalSeconds)) - contentOffsetX + (pillWidth / 2)
                Button(action: { onAddEnding?() }) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0xD9/255.0, green: 0xD9/255.0, blue: 0xD9/255.0))
                        .frame(width: pillWidth, height: 48)
                        .overlay(
                            Text("+ Add ending")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)
                        )
                }
                // Horizontally placed at the end of the filmstrip; vertically in the top lane
                .offset(x: pillX, y: -((stripHeight + spacingAboveStrip + rulerHeight)/2) - 10)
            }
            // Audio/Text stacked buttons to the left of playhead
            .overlay(alignment: .center) {
                VStack(spacing: 10) {
                    Button(action: { onAddAudio?() }) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 0xD9/255.0, green: 0xD9/255.0, blue: 0xD9/255.0))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image("quaver")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                                    .foregroundColor(.black)
                            )
                    }
                    Button(action: { onAddText?() }) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 0xD9/255.0, green: 0xD9/255.0, blue: 0xD9/255.0))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image("letter-t")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 15, height: 15)
                                    .foregroundColor(.black)
                            )
                    }
                }
                .offset(x: -70, y: -((stripHeight + spacingAboveStrip + rulerHeight)/2) + 60)
            }
            // Plus button under 00:03 tick (scrolls with timeline)
            .overlay(alignment: .center) {
                let plusX: CGFloat = (state.pixelsPerSecond * 3) - contentOffsetX
                PhotosPicker(selection: $selectedVideoItem, matching: .videos, photoLibrary: .shared()) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0xD9/255.0, green: 0xD9/255.0, blue: 0xD9/255.0))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image("iconplus")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundColor(.black)
                        )
                }
                .offset(x: plusX, y: -((stripHeight + spacingAboveStrip + rulerHeight)/2) - 10)
                .zIndex(1)
            }
            .onChange(of: selectedVideoItem) { _ in
                Task { await handlePickedVideo() }
            }
            .onChange(of: state.currentTime) { _ in
                guard !state.isScrubbing else { return }
                let center = geo.size.width / 2
                let target = CGFloat(seconds(state.currentTime)) * state.pixelsPerSecond - center
                withAnimation(.linear(duration: 0.1)) {
                    contentOffsetX = max(0, target)
                }
            }
            .onAppear {
                state.pixelsPerSecond = max(minPPS, min(maxPPS, state.pixelsPerSecond))
            }
            .gesture(magnifyGesture(geo: geo))
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.08))
    }

    private func seconds(_ t: CMTime) -> Double { max(0.0, CMTimeGetSeconds(t)) }

    // MARK: - Video picker state
    @State private var selectedVideoItem: PhotosPickerItem? = nil
    @State private var pickedVideoURL: URL? = nil

    private func handlePickedVideo() async {
        guard let item = selectedVideoItem else { return }
        // SwiftUI PhotosPicker (iOS 16+) exposes Transferable; use Data approach then persist to Documents
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "mov"
                let dest = docs.appendingPathComponent("picked_\(UUID().uuidString).\(ext)")
                try data.write(to: dest, options: .atomic)
                // Append to editor timeline
                await MainActor.run {
                    Task { await state.appendClip(url: dest) }
                }
                print("[Timeline] picked video saved → \(dest.lastPathComponent)")
            } else {
                print("[Timeline] picker returned no data")
            }
        } catch {
            print("[Timeline] picker error: \(error.localizedDescription)")
        }
        // Reset selection for subsequent picks
        await MainActor.run { selectedVideoItem = nil }
    }

    private func thumbWidth(geo: GeometryProxy) -> CGFloat { max(24, state.pixelsPerSecond) }

    // (Track row helpers removed during revert)

    private func dragGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($dragDX) { value, stateDX, _ in
                state.isScrubbing = true
                stateDX = -value.translation.width // negative to move content as finger moves
                let deltaSeconds = (value.translation.width / state.pixelsPerSecond)
                let newS = seconds(state.currentTime) + Double(deltaSeconds)
                let clamped = max(0.0, min(seconds(state.duration), newS))
                state.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), precise: true)
            }
            .onEnded { value in
                let center = geo.size.width / 2
                let target = CGFloat(seconds(state.currentTime)) * state.pixelsPerSecond - center
                contentOffsetX = max(0, target)
                state.isScrubbing = false
            }
    }

    private func magnifyGesture(geo: GeometryProxy) -> some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.01)
            .updating($pinchScale) { value, scale, _ in
                scale = value
            }
            .onEnded { value in
                let oldPPS = state.pixelsPerSecond
                let newPPS = max(minPPS, min(maxPPS, oldPPS * value))
                // Keep current time centered after zoom
                let center = geo.size.width / 2
                state.pixelsPerSecond = newPPS
                let target = CGFloat(seconds(state.currentTime)) * newPPS - center
                contentOffsetX = max(0, target)
            }
    }

    private func rulerOverlay(width: CGFloat, center: CGFloat) -> some View {
        let step: Double = 1.0
        let visibleStart = max(0.0, (contentOffsetX / state.pixelsPerSecond))
        let visibleEnd = max(visibleStart, (contentOffsetX + width) / state.pixelsPerSecond)
        let start = Int(floor(visibleStart / step))
        let end = Int(ceil(visibleEnd / step))
        let majorTickHeight: CGFloat = 12
        let bottomInset: CGFloat = 2
        return ZStack(alignment: .topLeading) {
            ForEach(start...end, id: \.self) { idx in
                let sec = Double(idx) * step
                let x = center + CGFloat(sec) * state.pixelsPerSecond - contentOffsetX
                if idx % 2 == 0 {
                    // Even seconds: full label (no tick)
                    Text(mmss(sec))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .position(x: x, y: 6)
                } else {
                    // Odd seconds: small dot (no tick)
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 3, height: 3)
                        .position(x: x, y: 10)
                }
            }
        }
    }

    private func timeString(_ t: CMTime) -> String { mmss(max(0.0, CMTimeGetSeconds(t))) }

    private func mmss(_ s: Double) -> String {
        let mins = Int(s) / 60
        let secs = Int(s) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - ScrollView content offset bridging
private struct ContentOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private extension View {
    func contentOffset(x: CGFloat) -> some View {
        self.background(GeometryReader { _ in Color.clear })
            .modifier(ScrollOffsetModifier(x: x))
    }
}

private struct ScrollOffsetModifier: ViewModifier {
    let x: CGFloat
    func body(content: Content) -> some View {
        content
            .overlay(ScrollViewOffsetApplier(x: x).allowsHitTesting(false))
    }
}

// Applies UIPan-less contentOffset by introspecting UIScrollView
private struct ScrollViewOffsetApplier: UIViewRepresentable {
    let x: CGFloat
    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if let scrollView = uiView.enclosingScrollView() {
                let target = CGPoint(x: max(0, x), y: 0)
                if scrollView.contentOffset != target {
                    scrollView.setContentOffset(target, animated: false)
                }
            }
        }
    }
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        var view: UIView? = self.superview
        while view != nil {
            if let sv = view as? UIScrollView { return sv }
            view = view?.superview
        }
        return nil
    }
}


