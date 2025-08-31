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
    @State private var didTapClip: Bool = false
    // Timeline dimensions
    private let stripHeight: CGFloat = 72       // filmstrip height
    private let rulerHeight: CGFloat = 32       // header/ruler height above filmstrip
    private let spacingAboveStrip: CGFloat = 8  // gap between ruler and filmstrip
    private let extraPlayheadExtension: CGFloat = 80 // extend playhead/HUD upward

    // Config
    private let minPPS: CGFloat = 20
    private let maxPPS: CGFloat = 300
    // Horizontal fine-tune so the first thumbnail sits relative to the playhead
    private let leftGap: CGFloat = -53.0
    // Horizontal nudge for empty-lane placeholders ("+ Add audio/text") to move the entire strip
    private let lanePlaceholderShiftX: CGFloat = 50

    private var headerOffsetY: CGFloat {
        -((stripHeight + spacingAboveStrip + rulerHeight)/2) - 10 - 50
    }

    // Extend playhead to span video + all timeline lanes below
    private var playheadHeight: CGFloat {
        let lanesCount: CGFloat = hasClip ? 2 : 0 // extra audio, text visible only when clips exist
        let stackedRows = TimelineStyle.videoRowHeight
            + lanesCount * TimelineStyle.laneRowHeight
            + lanesCount * TimelineStyle.rowSpacing
        return rulerHeight + spacingAboveStrip + stackedRows + extraPlayheadExtension
    }

    private var hasClip: Bool {
        !state.clips.isEmpty && CMTimeGetSeconds(state.totalDuration) > 0
    }

    // Centralized vertical anchors so both states (no-clip/has-clip) align consistently
    private var rowsBaseY: CGFloat { -((stripHeight + spacingAboveStrip + rulerHeight)/2) - 10 - 50 }
    private var filmstripCenterY: CGFloat { rowsBaseY + (TimelineStyle.videoRowHeight / 2) }
    private var noClipButtonDelta: CGFloat { hasClip ? 0 : 120 }
    private var clipButtonDelta: CGFloat { hasClip ? 80 : 0 }
    private var audioButtonCenterY: CGFloat { (filmstripCenterY - 26) + noClipButtonDelta + clipButtonDelta - 15 }
    private var textButtonCenterY: CGFloat { (filmstripCenterY + 26) + noClipButtonDelta + clipButtonDelta - 15 }

    

    // MARK: - Rows (split out for compiler)
    @ViewBuilder private func videoRow(_ geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            let leadingInset = max(0, (geo.size.width / 2) + leftGap)
            let trailingInset = max(0, (geo.size.width / 2) - leftGap) // mirror so end can center under playhead
            Color.clear.frame(width: leadingInset, height: TimelineStyle.videoRowHeight)
            ForEach(Array(state.clips.enumerated()), id: \.element.id) { _, clip in
                let clipWidth = CGFloat(max(0, CMTimeGetSeconds(clip.duration))) * state.pixelsPerSecond
                ZStack(alignment: .leading) {
                    // CapCut-style selection cell behind the entire clip
                    if state.selectedClipId == clip.id {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white)
                            .frame(width: clipWidth + 16, height: TimelineStyle.videoRowHeight + 12)
                            .offset(x: -8, y: -6)
                            .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1)
                            .zIndex(-1)
                    }
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: clipWidth, height: TimelineStyle.videoRowHeight)
                        .overlay(
                            // Keep stroke off; selection is represented by the white cell + bottom bar
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.clear, lineWidth: 0)
                        )
                    HStack(spacing: 0) {
                        let count = max(1, clip.thumbnails.count)
                        ForEach(0..<count, id: \.self) { i in
                            let img = i < clip.thumbnails.count ? clip.thumbnails[i] : UIImage()
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: max(24, state.pixelsPerSecond), height: TimelineStyle.videoRowHeight)
                                .clipped()
                        }
                    }
                    // Blue bottom bar to match CapCut visual
                    if state.selectedClipId == clip.id {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: clipWidth, height: 2)
                            .offset(y: (TimelineStyle.videoRowHeight / 2) - 1)
                    }
                }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    TapGesture().onEnded {
                        let wasSelected = (state.selectedClipId == clip.id)
                        state.selectedClipId = wasSelected ? nil : clip.id
                        didTapClip = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
            }
            // trailing spacer so the last frame can scroll until centered on the playhead
            Color.clear.frame(width: trailingInset, height: TimelineStyle.videoRowHeight)
        }
        .frame(height: TimelineStyle.videoRowHeight)
    }

    // Removed: originalAudioRow — original audio should not display as a waveform lane.

    @ViewBuilder private func extraAudioRow(_ geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            let leadingInset = max(0, (geo.size.width / 2) + leftGap)
            let trailingInset = max(0, (geo.size.width / 2) - leftGap)
            // Nudge start and shift entire lane ~400pt left (affects placeholder and items)
            Color.clear.frame(width: leadingInset + 2 + lanePlaceholderShiftX - 400, height: TimelineStyle.laneRowHeight)
            let totalWidth = CGFloat(max(0, CMTimeGetSeconds(state.totalDuration))) * state.pixelsPerSecond
            if state.audioTracks.isEmpty {
                // Make placeholder span the full timeline length so edits reflect exact duration
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.18))
                    .frame(width: totalWidth, height: TimelineStyle.laneRowHeight)
                    .overlay(
                        HStack { Text("+ Add audio").font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.9)); Spacer() }
                            .padding(.horizontal, 12)
                            .padding(.leading, 0)
                    )
            } else {
                // Hide the "+ Add audio" placeholder; show user-added audio items only
                ForEach(Array(state.audioTracks.enumerated()), id: \.element.id) { _, t in
                    let startX = CGFloat(max(0, CMTimeGetSeconds(t.start))) * state.pixelsPerSecond
                    let width = CGFloat(max(0, CMTimeGetSeconds(t.duration))) * state.pixelsPerSecond
                    Color.clear.frame(width: startX)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green.opacity(0.25))
                        .frame(width: width, height: TimelineStyle.laneRowHeight)
                }
            }
            // trailing inset so the last lane content can center under the playhead
            Color.clear.frame(width: trailingInset, height: TimelineStyle.laneRowHeight)
        }
        .frame(height: TimelineStyle.laneRowHeight)
        .offset(x: -200)
        .overlay(alignment: .topLeading) {
            let leadingInset = max(0, (geo.size.width / 2) + leftGap)
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
            // Move an additional ~100pt left from previous placement (total ~400pt)
            .offset(x: leadingInset + 2 + lanePlaceholderShiftX - 460, y: (TimelineStyle.laneRowHeight - 34) / 2)
            .zIndex(3)
        }
    }

    @ViewBuilder private func textRow(_ geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            let leadingInset = max(0, (geo.size.width / 2) + leftGap)
            let trailingInset = max(0, (geo.size.width / 2) - leftGap)
            // Nudge start and shift entire lane ~400pt left (affects placeholder and items)
            Color.clear.frame(width: leadingInset + 2 + lanePlaceholderShiftX - 400, height: TimelineStyle.laneRowHeight)
            let totalWidth = CGFloat(max(0, CMTimeGetSeconds(state.totalDuration))) * state.pixelsPerSecond
            if state.textOverlays.isEmpty {
                // Make placeholder span the full timeline length so edits reflect exact duration
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.18))
                    .frame(width: totalWidth, height: TimelineStyle.laneRowHeight)
                    .overlay(
                        HStack { Text("+ Add text").font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.9)); Spacer() }
                            .padding(.horizontal, 12)
                            .padding(.leading, 0)
                    )
            } else {
                ForEach(state.textOverlays, id: \.id) { t in
                    let width = CGFloat(max(0, CMTimeGetSeconds(t.duration))) * state.pixelsPerSecond
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.2))
                        .overlay(Text(t.base.string).font(.system(size: 11, weight: .semibold)).foregroundColor(.white).padding(4), alignment: .leading)
                        .frame(width: width, height: TimelineStyle.laneRowHeight)
                }
            }
            // trailing inset so the last lane content can center under the playhead
            Color.clear.frame(width: trailingInset, height: TimelineStyle.laneRowHeight)
        }
        .frame(height: TimelineStyle.laneRowHeight)
        .offset(x: -200)
        .overlay(alignment: .topLeading) {
            let leadingInset = max(0, (geo.size.width / 2) + leftGap)
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
            // Move an additional ~100pt left from previous placement (total ~400pt)
            .offset(x: leadingInset + 2 + lanePlaceholderShiftX - 460, y: (TimelineStyle.laneRowHeight - 34) / 2)
            .zIndex(3)
        }
    }
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Stack ruler above lanes with a small gap
                VStack(spacing: spacingAboveStrip) {
                    // Ruler overlay (seconds ticks) in header
                    rulerOverlay(width: geo.size.width, center: geo.size.width / 2)
                        .frame(height: rulerHeight)
                        .offset(y: -105) // raise ruler vertically by ~105pt total

                    // Shared horizontal scroller containing stacked rows. Keep header/ruler in original position (no extra offset here)
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(spacing: TimelineStyle.rowSpacing) {
                            videoRow(geo)
                            if hasClip {
                                extraAudioRow(geo)
                                textRow(geo)
                            }
                        }
                    }
                    .contentOffset(x: contentOffsetX + dragDX)
                    .gesture(dragGesture(geo: geo))
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if !didTapClip { state.selectedClipId = nil }
                            didTapClip = false
                        }
                    )
                    // Align stacked rows with playhead like before. Keep same vertical offset as previous single-row timeline
                    .offset(y: -((stripHeight + spacingAboveStrip + rulerHeight)/2) - 10 - 50)
                    .zIndex(0)

                }

                // Centered playhead line spanning ruler + gap + strip
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: playheadHeight)

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
            
            // Audio quick button (aligned by centralized anchors)
            .overlay(alignment: .center) {
                if !hasClip {
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
                .offset(x: -60, y: audioButtonCenterY)
                .zIndex(3)
                }
            }
            // Text quick button (aligned by centralized anchors)
            .overlay(alignment: .center) {
                if !hasClip {
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
                .offset(x: -60, y: textButtonCenterY)
                .zIndex(3)
                }
            }
            // Plus button aligned with filmstrip lane center; scrolls with timeline
            .overlay(alignment: .center) {
                // In a center-aligned overlay, 0 is the screen center. Offset by seconds*pixelsPerSecond, minus current scroll.
                let plusX: CGFloat = (state.pixelsPerSecond * 3) - (contentOffsetX + dragDX)
                // Vertically center on the video (filmstrip) row; when there is no clip, nudge the plus 20pt lower
                let baseY = -((stripHeight + spacingAboveStrip + rulerHeight)/2) - 10 - 50
                let plusY = baseY + (TimelineStyle.videoRowHeight / 2) + (hasClip ? -10 : 20)
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
                .offset(x: plusX, y: plusY)
                .zIndex(1)
            }
            // Fixed left time counter (mm:ss / mm:ss) drawn last to sit above everything
            .overlay(alignment: .topLeading) {
                Text("\(mmss(seconds(state.currentTime))) / \(mmss(seconds(state.duration)))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.leading, 12)
                    .padding(.top, 0)
                    .offset(y: -10)
                    .zIndex(1000)
                    .allowsHitTesting(false)
            }
            .onChange(of: selectedVideoItem) { _ in
                Task { await handlePickedVideo() }
            }
            .onChange(of: state.currentTime) { _ in
                guard !state.isScrubbing else { return }
                let center = geo.size.width / 2
                // Keep filmstrip centered on the playhead using the same mapping as drag
                let target = CGFloat(seconds(state.currentTime)) * state.pixelsPerSecond - center
                withAnimation(.linear(duration: 0.08)) {
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


