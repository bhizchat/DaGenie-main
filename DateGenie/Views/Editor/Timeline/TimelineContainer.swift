import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

struct TimelineContainer: View {
    @ObservedObject var state: EditorState
    // Optional action for the \"Add ending\" pill
    let onAddEnding: (() -> Void)?
    // Optional actions for Audio/Text quick-add buttons
    let onAddAudio: (() -> Void)?
    let onAddText: (() -> Void)?

    init(state: EditorState,
         onAddAudio: (() -> Void)? = nil,
         onAddText: (() -> Void)? = nil,
         onAddEnding: (() -> Void)? = nil) {
        self.state = state
        self.onAddAudio = onAddAudio
        self.onAddText = onAddText
        self.onAddEnding = onAddEnding
    }

    // View-local scroll state
    @State private var contentOffsetX: CGFloat = 0
    @GestureState private var dragDX: CGFloat = 0
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var didTapClip: Bool = false
    // Audio drag helpers
    @State private var draggingAudioId: UUID? = nil
    @State private var audioDragStartSeconds: Double = 0
    // Observed native ScrollView horizontal offset (PreferenceKey-based)
    @State private var observedOffsetX: CGFloat = 0
    // Timeline dimensions
    private let stripHeight: CGFloat = 72       // filmstrip height
    private let rulerHeight: CGFloat = 32       // header/ruler height above filmstrip
    private let spacingAboveStrip: CGFloat = 8  // gap between ruler and filmstrip
    private let extraPlayheadExtension: CGFloat = 80 // extend playhead/HUD upward

    // Config
    private let minPPS: CGFloat = 20
    private let maxPPS: CGFloat = 300
    // Horizontal fine-tune so the first thumbnail sits relative to the playhead
    private let leftGap: CGFloat = 0.0
    // Horizontal nudge for empty-lane placeholders ("+ Add audio/text") to move the entire strip
    private let lanePlaceholderShiftX: CGFloat = 50

    // Selection styling (CapCut-like)
    private let selectionPadH: CGFloat = 8
    private let selectionPadV: CGFloat = 6
    private let selectionHandleWidth: CGFloat = 35
    private let selectionHandleCorner: CGFloat = 0

    private var headerOffsetY: CGFloat {
        -((stripHeight + spacingAboveStrip + rulerHeight)/2) - 10 - 50
    }

    // Shared rows vertical offset used by both the ScrollView rows and the selection overlay
    private var rowsOffsetY: CGFloat {
        -((stripHeight + spacingAboveStrip + rulerHeight)/2) - 10 - 50
    }

    // Fixed container height for the stacked rows to prevent layout jumps when overlay appears
    private var rowsStackHeight: CGFloat {
        let lanesCount: CGFloat = hasClip ? 2 : 0
        return TimelineStyle.videoRowHeight
             + lanesCount * TimelineStyle.laneRowHeight
             + lanesCount * TimelineStyle.rowSpacing
    }

    // Extend playhead to span video + all timeline lanes below
    private var playheadHeight: CGFloat {
        return rulerHeight + spacingAboveStrip + stackedRowsHeight + extraPlayheadExtension
    }

    private var hasClip: Bool {
        !state.clips.isEmpty && CMTimeGetSeconds(state.totalDuration) > 0
    }

    // Computed rows height used for layout and publishing preferred height
    private var lanesCount: CGFloat { hasClip ? 2 : 0 }
    private var stackedRowsHeight: CGFloat {
        TimelineStyle.videoRowHeight
        + lanesCount * TimelineStyle.laneRowHeight
        + lanesCount * TimelineStyle.rowSpacing
    }
    private var preferredHeight: CGFloat {
        rulerHeight + spacingAboveStrip + stackedRowsHeight
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
                // Use trimmed duration if available
                let rawSeconds = max(0, CMTimeGetSeconds(clip.duration))
                let trimmedEnd = CMTimeGetSeconds(clip.trimEnd ?? clip.duration)
                let trimmedStart = CMTimeGetSeconds(clip.trimStart)
                let effectiveSeconds = max(0, min(rawSeconds, trimmedEnd) - max(0, trimmedStart))
                let clipWidth = CGFloat(effectiveSeconds) * state.pixelsPerSecond
                ZStack(alignment: .leading) {
                    // Selection card behind content aligned to exact clip start/end with clear white surround
                    if state.selectedClipId == clip.id {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white, lineWidth: 3)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white)
                            )
                            .frame(width: clipWidth, height: TimelineStyle.videoRowHeight)
                            .offset(x: 0, y: 0)
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
                    .frame(width: clipWidth, height: TimelineStyle.videoRowHeight, alignment: .leading)
                    .clipped()
                    // Blue bottom bar to match CapCut visual
                    if state.selectedClipId == clip.id {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: clipWidth, height: 2)
                            .offset(y: (TimelineStyle.videoRowHeight / 2) - 1)
                    }
                }
                .frame(width: clipWidth, height: TimelineStyle.videoRowHeight, alignment: .leading)
                // Per-clip handle overlays removed; handled by global overlay for accurate placement
                .contentShape(Rectangle())
                .zIndex(state.selectedClipId == clip.id ? 100 : 0)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    TapGesture().onEnded {
                        let wasSelected = (state.selectedClipId == clip.id)
                        state.selectedClipId = wasSelected ? nil : clip.id
                        if !wasSelected { state.selectedAudioId = nil }
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
            let center = geo.size.width / 2
            let leadingInset = max(0, center + leftGap)
            let trailingInset = max(0, center - leftGap)
            let totalSeconds = max(0, CMTimeGetSeconds(state.totalDuration))
            let timelineWidth = CGFloat(totalSeconds) * state.pixelsPerSecond

            // Leading inset so time 0 sits under the playhead
            Color.clear.frame(width: leadingInset, height: TimelineStyle.laneRowHeight)

            // Fixed-width lane; overlay items positioned absolutely
            Rectangle().fill(Color.clear)
                .frame(width: timelineWidth, height: TimelineStyle.laneRowHeight)
                .overlay(alignment: .topLeading) {
                    if state.audioTracks.isEmpty {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.18))
                            .frame(width: timelineWidth, height: TimelineStyle.laneRowHeight)
                            .overlay(
                                HStack { Text("+ Add audio").font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.9)); Spacer() }
                                    .padding(.leading, 56)
                                , alignment: .leading
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onAddAudio?() }
                    } else {
                        ForEach(Array(state.audioTracks.enumerated()), id: \.element.id) { _, t in
                            let startX = CGFloat(max(0, CMTimeGetSeconds(t.start))) * state.pixelsPerSecond
                            let width = CGFloat(max(0, CMTimeGetSeconds(t.duration))) * state.pixelsPerSecond

                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(red: 0xE3/255.0, green: 0x9F/255.0, blue: 0xF6/255.0, opacity: 0.85))

                                // Waveform inside the pill
                                WaveformView(samples: t.waveformSamples, color: Color(red: 0.94, green: 0.90, blue: 1.00))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 6)
                                    .allowsHitTesting(false)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                // File name at top-left
                                Text(t.displayName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .padding(.top, 4)
                                    .padding(.leading, 6)
                                    .allowsHitTesting(false)
                            }
                            .frame(width: width, height: TimelineStyle.laneRowHeight)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(state.selectedAudioId == t.id ? Color.white : Color.clear, lineWidth: 2)
                            )
                            .offset(x: startX)
                            .contentShape(Rectangle())
                            .highPriorityGesture(
                                TapGesture().onEnded {
                                    let was = (state.selectedAudioId == t.id)
                                    state.selectedAudioId = was ? nil : t.id
                                    if !was { state.selectedClipId = nil }
                                    didTapClip = true
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            )
                            .gesture(
                                LongPressGesture(minimumDuration: 0.25)
                                    .sequenced(before: DragGesture(minimumDistance: 1))
                                    .onChanged { value in
                                        switch value {
                                        case .first(true):
                                            if draggingAudioId != t.id {
                                                draggingAudioId = t.id
                                                audioDragStartSeconds = max(0, CMTimeGetSeconds(t.start))
                                            }
                                        case .second(true, let drag?):
                                            let delta = Double(drag.translation.width / max(1, state.pixelsPerSecond))
                                            let newStart = audioDragStartSeconds + delta
                                            state.moveAudio(id: t.id, toStartSeconds: newStart)
                                        default:
                                            break
                                        }
                                    }
                                    .onEnded { _ in
                                        draggingAudioId = nil
                                        Task { await state.rebuildCompositionForPreview() }
                                    }
                            )
                        }
                    }
                }

            // Trailing inset so last content can center under the playhead
            Color.clear.frame(width: trailingInset, height: TimelineStyle.laneRowHeight)
        }
        .frame(height: TimelineStyle.laneRowHeight)
        .overlay(alignment: .topLeading) {
            if state.audioTracks.isEmpty {
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
                // Position near the playhead using the same inset as the filmstrip
                .offset(x: leadingInset + 2, y: (TimelineStyle.laneRowHeight - 34) / 2)
                .zIndex(3)
            }
        }
    }

    @ViewBuilder private func textRow(_ geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            let center = geo.size.width / 2
            let leadingInset = max(0, center + leftGap)
            let trailingInset = max(0, center - leftGap)
            let totalSeconds = max(0, CMTimeGetSeconds(state.totalDuration))
            let timelineWidth = CGFloat(totalSeconds) * state.pixelsPerSecond

            Color.clear.frame(width: leadingInset, height: TimelineStyle.laneRowHeight)

            Rectangle().fill(Color.clear)
                .frame(width: timelineWidth, height: TimelineStyle.laneRowHeight)
                .overlay(alignment: .topLeading) {
                    if state.textOverlays.isEmpty {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.18))
                            .frame(width: timelineWidth, height: TimelineStyle.laneRowHeight)
                            .overlay(
                                HStack { Text("+ Add text").font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.9)); Spacer() }
                                    .padding(.leading, 56)
                                , alignment: .leading
                            )
                    } else {
                        ForEach(state.textOverlays, id: \.id) { t in
                            let startX = CGFloat(max(0, CMTimeGetSeconds(t.start))) * state.pixelsPerSecond
                            let width = CGFloat(max(0, CMTimeGetSeconds(t.duration))) * state.pixelsPerSecond
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue.opacity(0.2))
                                .overlay(Text(t.base.string).font(.system(size: 11, weight: .semibold)).foregroundColor(.white).padding(4), alignment: .leading)
                                .frame(width: width, height: TimelineStyle.laneRowHeight)
                                .offset(x: startX)
                        }
                    }
                }

            Color.clear.frame(width: trailingInset, height: TimelineStyle.laneRowHeight)
        }
        .frame(height: TimelineStyle.laneRowHeight)
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
            // Position near the playhead using the same inset as the filmstrip
            .offset(x: leadingInset + 2, y: (TimelineStyle.laneRowHeight - 34) / 2)
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

                    // Shared horizontal scroller and selection overlay share the same vertical offset
                    ZStack(alignment: .topLeading) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(spacing: TimelineStyle.rowSpacing) {
                                videoRow(geo)
                                if hasClip {
                                    extraAudioRow(geo)
                                    textRow(geo)
                                }
                            }
                            .background(
                                ScrollViewBridge(targetX: contentOffsetX) { x, isTracking, isDragging, isDecel in
                                    observedOffsetX = x
                                    let center = geo.size.width / 2
                                    let leadingInset = max(0, center + leftGap)
                                    // Map scroll -> time only when the user is interacting
                                    if (isTracking || isDragging || isDecel) {
                                        let raw = (x - leadingInset + center) / max(1, state.pixelsPerSecond)
                                        let dur = max(0.0, CMTimeGetSeconds(state.totalDuration))
                                        let t = max(0.0, min(Double(raw), dur))
                                        state.seek(to: CMTime(seconds: t, preferredTimescale: 600), precise: false)
                                    }
                                }
                            )
                        }
                        .coordinateSpace(name: "timelineScroll")
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                if !didTapClip {
                                    state.selectedClipId = nil
                                    state.selectedAudioId = nil
                                }
                                didTapClip = false
                            }
                        )

                        // Selection overlay (frame + handles) positioned in the SAME coordinate space as rows
                        if let s = state.selectedClipStartSeconds,
                           let e = state.selectedClipEndSeconds,
                           e > s {
                            let pps = state.pixelsPerSecond
                            let center = geo.size.width / 2
                            let leadingInset = max(0, center + leftGap)
                            // Use the observed ScrollView offset and include leading inset used by rows
                            let startX = leadingInset + CGFloat(s) * pps - observedOffsetX
                            let endX   = leadingInset + CGFloat(e) * pps - observedOffsetX
                            let selW   = endX - startX

                            Group {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white, lineWidth: 3)
                                    .frame(width: selW, height: TimelineStyle.videoRowHeight)
                                    .position(x: startX + selW / 2,
                                              y: TimelineStyle.videoRowHeight / 2)
                                    .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1)

                                // Left handle
                                ZStack {
                                    RoundedRectangle(cornerRadius: selectionHandleCorner)
                                        .fill(Color.white)
                                        .frame(width: selectionHandleWidth, height: TimelineStyle.videoRowHeight - 4)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.black.opacity(0.9))
                                                .frame(width: selectionHandleWidth * 0.35,
                                                       height: max(8, TimelineStyle.videoRowHeight - 12))
                                        )
                                }
                                .position(x: startX - selectionHandleWidth / 2,
                                          y: TimelineStyle.videoRowHeight / 2)
                                .zIndex(200)

                                // Right handle
                                ZStack {
                                    RoundedRectangle(cornerRadius: selectionHandleCorner)
                                        .fill(Color.white)
                                        .frame(width: selectionHandleWidth, height: TimelineStyle.videoRowHeight - 4)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.black.opacity(0.9))
                                                .frame(width: selectionHandleWidth * 0.35,
                                                       height: max(8, TimelineStyle.videoRowHeight - 12))
                                        )
                                }
                                .position(x: endX + selectionHandleWidth / 2,
                                          y: TimelineStyle.videoRowHeight / 2)
                                .zIndex(200)
                            }
                            // Ensure overlay does not intercept timeline gestures
                            .allowsHitTesting(false)
                        }
                    }
                    // Align stacked rows (and overlay) with playhead like before
                    .frame(height: stackedRowsHeight)
                    .offset(y: rowsOffsetY)
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
            // Plus button fixed to the trailing edge; does not move with scroll/zoom
            .overlay(alignment: .trailing) {
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
                .padding(.trailing, 12)
                .offset(y: plusY)
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
                let leadingInset = max(0, center + leftGap)
                // Ensure start frame (time 0) aligns exactly under the playhead for the first clip when currentTime == 0
                let target = leadingInset + CGFloat(seconds(state.currentTime)) * state.pixelsPerSecond - center
                contentOffsetX = target
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
        // Deprecated: let UIScrollView own horizontal pan; we keep function to avoid breaking calls
        DragGesture(minimumDistance: 1)
            .onChanged { _ in }
            .onEnded { _ in }
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
        let leadingInset = max(0, center + leftGap)
        let visibleStart = max(0.0, ((observedOffsetX - leadingInset) / state.pixelsPerSecond))
        let visibleEnd = max(visibleStart, ((observedOffsetX - leadingInset + width) / state.pixelsPerSecond))
        let start = Int(floor(visibleStart / step))
        let end = Int(ceil(visibleEnd / step))
        let majorTickHeight: CGFloat = 12
        let bottomInset: CGFloat = 2
        return ZStack(alignment: .topLeading) {
            ForEach(start...end, id: \.self) { idx in
                let sec = Double(idx) * step
                let x = leadingInset + CGFloat(sec) * state.pixelsPerSecond - observedOffsetX
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

// PreferenceKey for observing timeline ScrollView horizontal offset
private struct TimelineScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}


