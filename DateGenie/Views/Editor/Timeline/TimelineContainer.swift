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
    // Programmatic scroll target should be opt-in; nil means "do not touch scroll view"
    @State private var programmaticX: CGFloat? = nil
    @GestureState private var dragDX: CGFloat = 0
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var didTapClip: Bool = false
    // Track whether the user (or deceleration) is currently driving the scroll view
    @State private var isScrollInteracting: Bool = false
    @State private var lastScrollEndedAt: CFTimeInterval = 0
    // Cooldown after zoom to avoid immediate follow bounce
    @State private var lastZoomEndedAt: CFTimeInterval = 0
    // Audio drag helpers
    @State private var draggingAudioId: UUID? = nil
    @State private var audioDragStartSeconds: Double = 0
    // Text drag helpers and scroll gating
    @State private var draggingTextId: UUID? = nil
    @State private var textDragStartSeconds: Double = 0
    // Freeze timeline scroll while dragging any lane item
    @State private var isDraggingLaneItem: Bool = false
    // Observed native ScrollView horizontal offset (PreferenceKey-based)
    @State private var observedOffsetX: CGFloat = 0
    // Global handle drag incremental delta trackers (avoid compounding)
    @State private var leftHandlePrevDX: CGFloat = 0
    @State private var rightHandlePrevDX: CGFloat = 0
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
    // MARK: - Fixed-playhead mapping helpers (single source of truth)
    private func screenScale() -> CGFloat { UIScreen.main.scale }
    private func leadingInset(for width: CGFloat) -> CGFloat {
        let center = width / 2
        let pxRoundedCenter = (center * screenScale()).rounded(.toNearestOrAwayFromZero) / screenScale()
        return max(0, pxRoundedCenter + leftGap)
    }
    private func timeForOffset(_ x: CGFloat, width: CGFloat, pps: CGFloat, duration: CMTime) -> CMTime {
        let center = width / 2
        let tSeconds = Double(max(0, (x - leadingInset(for: width) + center) / max(1, pps)))
        let dur = max(0.0, CMTimeGetSeconds(duration))
        return CMTime(seconds: min(tSeconds, dur), preferredTimescale: 600)
    }
    private func offsetForTime(_ time: CMTime, width: CGFloat, pps: CGFloat) -> CGFloat {
        let center = width / 2
        let t = max(0.0, CMTimeGetSeconds(time))
        let x = leadingInset(for: width) + CGFloat(t) * pps - center
        let s = screenScale()
        return (x * s).rounded(.toNearestOrAwayFromZero) / s
    }

    // MARK: - Scroll handler (extracted for type-checking performance)
    private func handleScrollEvent(x: CGFloat,
                                   isTracking: Bool,
                                   isDragging: Bool,
                                   isDecel: Bool,
                                   geo: GeometryProxy) {
        observedOffsetX = x
        // Consider any of these phases an interaction; mirror to scrubbing flag
        let interacting = (isTracking || isDragging || isDecel)
        if isScrollInteracting != interacting {
            isScrollInteracting = interacting
            state.isScrubbing = interacting
            if interacting {
                state.beginScrub()
            } else {
                lastScrollEndedAt = CACurrentMediaTime()
                state.endScrub()
            }
        }
        // Map scroll → time only while user (or deceleration) is driving.
        if interacting {
            let ct = timeForOffset(x, width: geo.size.width,
                                   pps: state.pixelsPerSecond,
                                   duration: state.totalDuration)
            state.scrub(to: ct)
        }
    }

    // MARK: - Small helpers to reduce type-check depth
    @ViewBuilder private func headerRuler(_ geo: GeometryProxy) -> some View {
        rulerOverlay(width: geo.size.width, center: geo.size.width / 2)
            .frame(height: rulerHeight)
            .offset(y: -105) // raise ruler vertically by ~105pt total
    }

    @ViewBuilder private func scrollerAndOverlays(_ geo: GeometryProxy) -> some View {
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
                    ScrollViewBridge(targetX: programmaticX,
                                     isScrollEnabled: !isDraggingLaneItem) { x, t, d, decel in
                        handleScrollEvent(x: x,
                                          isTracking: t,
                                          isDragging: d,
                                          isDecel: decel,
                                          geo: geo)
                    }
                )
            }
            .coordinateSpace(name: "timelineScroll")
            .simultaneousGesture(
                TapGesture().onEnded {
                    if !didTapClip {
                        state.selectedClipId = nil
                        state.selectedAudioId = nil
                        state.selectedTextId = nil
                        // Explicitly close the Edit toolbar on global deselection
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: Notification.Name("CloseEditToolbarForDeselection"), object: nil)
                        }
                    }
                    didTapClip = false
                }
            )

            // Selection overlay (frame + handles) positioned in the SAME coordinate space as rows
            if let s = state.selectedClipStartSeconds,
               let e = state.selectedClipEndSeconds,
               e > s {
                let pps = state.pixelsPerSecond
                // Use unified mapping for precise placement
                let startX = (offsetForTime(CMTime(seconds: s, preferredTimescale: 600), width: geo.size.width, pps: pps) + geo.size.width/2) - observedOffsetX
                let endX   = (offsetForTime(CMTime(seconds: e, preferredTimescale: 600), width: geo.size.width, pps: pps) + geo.size.width/2) - observedOffsetX
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

            // Global overlay for AUDIO selection (absolute coordinates)
            if let sA = state.selectedAudioStartSeconds,
               let eA = state.selectedAudioEndSeconds,
               eA > sA, let a = state.selectedAudio {
                let pps = state.pixelsPerSecond
                let startX = (offsetForTime(CMTime(seconds: sA, preferredTimescale: 600), width: geo.size.width, pps: pps) + geo.size.width/2) - observedOffsetX
                let endX   = (offsetForTime(CMTime(seconds: eA, preferredTimescale: 600), width: geo.size.width, pps: pps) + geo.size.width/2) - observedOffsetX
                let y = TimelineStyle.videoRowHeight + TimelineStyle.rowSpacing + (TimelineStyle.laneRowHeight / 2)

                // Frame (optional outline to match video look)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: endX - startX, height: TimelineStyle.laneRowHeight)
                    .position(x: startX + (endX - startX)/2, y: y)
                    .allowsHitTesting(false)

                // Left handle
                EdgeHandle(height: TimelineStyle.laneRowHeight, width: selectionHandleWidth, onDrag: { dx in
                    if !isDraggingLaneItem { isDraggingLaneItem = true }
                    let deltaSec = Double((dx - leftHandlePrevDX) / max(1, pps))
                    leftHandlePrevDX = dx
                    Task { await state.trimAudio(id: a.id, leftDeltaSeconds: deltaSec) }
                }, onEnd: {
                    leftHandlePrevDX = 0
                    isDraggingLaneItem = false
                })
                .highPriorityGesture(DragGesture(minimumDistance: 0))
                .position(x: startX - selectionHandleWidth/2, y: y)
                .zIndex(220)
                .onDisappear { leftHandlePrevDX = 0 }

                // Right handle
                EdgeHandle(height: TimelineStyle.laneRowHeight, width: selectionHandleWidth, onDrag: { dx in
                    if !isDraggingLaneItem { isDraggingLaneItem = true }
                    let deltaSec = Double((dx - rightHandlePrevDX) / max(1, pps))
                    rightHandlePrevDX = dx
                    Task { await state.trimAudio(id: a.id, rightDeltaSeconds: deltaSec) }
                }, onEnd: {
                    rightHandlePrevDX = 0
                    isDraggingLaneItem = false
                })
                .highPriorityGesture(DragGesture(minimumDistance: 0))
                .position(x: endX + selectionHandleWidth/2, y: y)
                .zIndex(220)
                .onDisappear { rightHandlePrevDX = 0 }
            }

            // Global overlay for TEXT selection (absolute coordinates)
            if let sT = state.selectedTextStartSeconds,
               let eT = state.selectedTextEndSeconds,
               eT > sT, let t = state.selectedText {
                let pps = state.pixelsPerSecond
                let startX = (offsetForTime(CMTime(seconds: sT, preferredTimescale: 600), width: geo.size.width, pps: pps) + geo.size.width/2) - observedOffsetX
                let endX   = (offsetForTime(CMTime(seconds: eT, preferredTimescale: 600), width: geo.size.width, pps: pps) + geo.size.width/2) - observedOffsetX
                let y = TimelineStyle.videoRowHeight + TimelineStyle.rowSpacing + TimelineStyle.laneRowHeight + TimelineStyle.rowSpacing + (TimelineStyle.laneRowHeight / 2)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: endX - startX, height: TimelineStyle.laneRowHeight)
                    .position(x: startX + (endX - startX)/2, y: y)
                    .allowsHitTesting(false)

                EdgeHandle(height: TimelineStyle.laneRowHeight, width: selectionHandleWidth, onDrag: { dx in
                    if !isDraggingLaneItem { isDraggingLaneItem = true }
                    let deltaSec = Double((dx - leftHandlePrevDX) / max(1, pps))
                    leftHandlePrevDX = dx
                    state.trimText(id: t.id, leftDeltaSeconds: deltaSec)
                }, onEnd: {
                    leftHandlePrevDX = 0
                    isDraggingLaneItem = false
                })
                .highPriorityGesture(DragGesture(minimumDistance: 0))
                .position(x: startX - selectionHandleWidth/2, y: y)
                .zIndex(220)
                .onDisappear { leftHandlePrevDX = 0 }

                EdgeHandle(height: TimelineStyle.laneRowHeight, width: selectionHandleWidth, onDrag: { dx in
                    if !isDraggingLaneItem { isDraggingLaneItem = true }
                    let deltaSec = Double((dx - rightHandlePrevDX) / max(1, pps))
                    rightHandlePrevDX = dx
                    state.trimText(id: t.id, rightDeltaSeconds: deltaSec)
                }, onEnd: {
                    rightHandlePrevDX = 0
                    isDraggingLaneItem = false
                })
                .highPriorityGesture(DragGesture(minimumDistance: 0))
                .position(x: endX + selectionHandleWidth/2, y: y)
                .zIndex(220)
                .onDisappear { rightHandlePrevDX = 0 }
            }
        }
        // Align stacked rows (and overlay) with playhead like before
        .frame(height: stackedRowsHeight)
        .offset(y: rowsOffsetY)
        .zIndex(0)
    }

    // Edge handle for global overlay (absolute positioning)
    private struct EdgeHandle: View {
        let height: CGFloat
        let width: CGFloat
        let onDrag: (CGFloat) -> Void // dx in points
        let onEnd: () -> Void         // reset bookkeeping per gesture
        let onBegin: (() -> Void)?
        @GestureState private var dx: CGFloat = 0
        @State private var didBegin: Bool = false
        init(height: CGFloat,
             width: CGFloat,
             onDrag: @escaping (CGFloat) -> Void,
             onEnd: @escaping () -> Void,
             onBegin: (() -> Void)? = nil) {
            self.height = height
            self.width = width
            self.onDrag = onDrag
            self.onEnd = onEnd
            self.onBegin = onBegin
        }
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.white)
                    .frame(width: width, height: height - 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.9))
                            .frame(width: width * 0.35,
                                   height: max(8, height - 12))
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dx) { v, st, _ in st = v.translation.width }
                    .onChanged { v in
                        if !didBegin { didBegin = true; onBegin?() }
                        onDrag(v.translation.width)
                    }
                    .onEnded { _ in onEnd() }
            )
        }
    }

    // Reusable trim handle pair used for audio/text lane items
    private struct TrimHandles: View {
        let height: CGFloat
        let handleWidth: CGFloat
        let corner: CGFloat
        let onLeftDrag: (CGFloat) -> Void   // dx in points
        let onRightDrag: (CGFloat) -> Void  // dx in points
        @GestureState private var leftDX: CGFloat = 0
        @GestureState private var rightDX: CGFloat = 0
        var body: some View {
            HStack {
                // Left handle
                ZStack {
                    RoundedRectangle(cornerRadius: corner)
                        .fill(Color.white)
                        .frame(width: handleWidth, height: height - 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.black.opacity(0.9))
                                .frame(width: handleWidth * 0.35,
                                       height: max(8, height - 12))
                        )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($leftDX) { v, st, _ in st = v.translation.width }
                        .onChanged { v in onLeftDrag(v.translation.width) }
                )

                Spacer(minLength: 0)

                // Right handle
                ZStack {
                    RoundedRectangle(cornerRadius: corner)
                        .fill(Color.white)
                        .frame(width: handleWidth, height: height - 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.black.opacity(0.9))
                                .frame(width: handleWidth * 0.35,
                                       height: max(8, height - 12))
                        )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($rightDX) { v, st, _ in st = v.translation.width }
                        .onChanged { v in onRightDrag(v.translation.width) }
                )
            }
            .padding(.horizontal, -handleWidth / 2)
        }
    }

    // Lightweight lane item for audio strips
    private struct AudioStripPill: View {
        let width: CGFloat
        let height: CGFloat
        let offsetX: CGFloat
        let title: String
        let samples: [Float]
        let isSelected: Bool
        let pps: CGFloat
        // Interactions
        let onTap: () -> Void
        let onBeginMove: () -> Void
        let onDragMove: (Double) -> Void   // delta seconds
        let onEndMove: () -> Void
        let onTrimLeft: (Double) -> Void   // delta seconds
        let onTrimRight: (Double) -> Void  // delta seconds

        var body: some View {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0xE3/255.0, green: 0x9F/255.0, blue: 0xF6/255.0, opacity: 0.85))

                WaveformView(samples: samples, color: Color(red: 0.94, green: 0.90, blue: 1.00))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.top, 4)
                    .padding(.leading, 6)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
            )
            .offset(x: offsetX)
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded { onTap() })
            .gesture(
                LongPressGesture(minimumDuration: 0.25)
                    .sequenced(before: DragGesture(minimumDistance: 1))
                    .onChanged { value in
                        switch value {
                        case .first(true): onBeginMove()
                        case .second(true, let drag?):
                            let deltaSec = Double(drag.translation.width / max(1, pps))
                            onDragMove(deltaSec)
                        default: break
                        }
                    }
                    .onEnded { _ in onEndMove() }
            )
        }
    }

    // Lightweight lane item for text strips
    private struct TextStripPill: View {
        let width: CGFloat
        let height: CGFloat
        let offsetX: CGFloat
        let text: String
        let isSelected: Bool
        let pps: CGFloat
        // Interactions
        let onTap: () -> Void
        let onBeginMove: () -> Void
        let onDragMove: (Double) -> Void
        let onEndMove: () -> Void
        let onTrimLeft: (Double) -> Void
        let onTrimRight: (Double) -> Void

        var body: some View {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.blue.opacity(0.2))
                .overlay(
                    Text(text)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(4), alignment: .leading
                )
                .frame(width: width, height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                )
                .offset(x: offsetX)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded { onTap() })
                .gesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .sequenced(before: DragGesture(minimumDistance: 1))
                        .onChanged { value in
                            switch value {
                            case .first(true): onBeginMove()
                            case .second(true, let drag?):
                                let deltaSec = Double(drag.translation.width / max(1, pps))
                                onDragMove(deltaSec)
                            default: break
                            }
                        }
                        .onEnded { _ in onEndMove() }
                )
        }
    }

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
                        if !wasSelected {
                            state.selectedAudioId = nil
                            state.selectedTextId = nil
                            // Ensure toolbar opens immediately on first selection
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: Notification.Name("OpenEditToolbarForSelection"), object: nil)
                            }
                        }
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
                            let startX: CGFloat = CGFloat(max(0, CMTimeGetSeconds(t.start + t.trimStart))) * state.pixelsPerSecond
                            let width: CGFloat = CGFloat(max(0, CMTimeGetSeconds(t.trimmedDuration))) * state.pixelsPerSecond
                            AudioStripPill(
                                width: width,
                                height: TimelineStyle.laneRowHeight,
                                offsetX: startX,
                                title: t.displayName,
                                samples: t.waveformSamples,
                                isSelected: state.selectedAudioId == t.id,
                                pps: state.pixelsPerSecond,
                                onTap: {
                                    let was = (state.selectedAudioId == t.id)
                                    state.selectedAudioId = was ? nil : t.id
                                    if !was {
                                        state.selectedClipId = nil
                                        state.selectedTextId = nil
                                        DispatchQueue.main.async {
                                            NotificationCenter.default.post(name: Notification.Name("OpenEditToolbarForSelection"), object: nil)
                                        }
                                    }
                                    didTapClip = true
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                },
                                onBeginMove: {
                                    if draggingAudioId != t.id {
                                        draggingAudioId = t.id
                                        audioDragStartSeconds = max(0, CMTimeGetSeconds(t.start))
                                        isDraggingLaneItem = true
                                    }
                                },
                                onDragMove: { deltaSec in
                                    let newStart = audioDragStartSeconds + deltaSec
                                    state.moveAudio(id: t.id, toStartSeconds: newStart)
                                },
                                onEndMove: {
                                    draggingAudioId = nil
                                    isDraggingLaneItem = false
                                    Task { await state.rebuildCompositionForPreview() }
                                },
                                onTrimLeft: { dxSec in
                                    Task { await state.trimAudio(id: t.id, leftDeltaSeconds: dxSec) }
                                },
                                onTrimRight: { dxSec in
                                    Task { await state.trimAudio(id: t.id, rightDeltaSeconds: dxSec) }
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
                            .contentShape(Rectangle())
                            .onTapGesture { onAddText?() }
                    } else {
                        ForEach(state.textOverlays, id: \.id) { t in
                            let startX: CGFloat = CGFloat(max(0, CMTimeGetSeconds(t.effectiveStart))) * state.pixelsPerSecond
                            let width: CGFloat = CGFloat(max(0, CMTimeGetSeconds(t.trimmedDuration))) * state.pixelsPerSecond
                            TextStripPill(
                                width: width,
                                height: TimelineStyle.laneRowHeight,
                                offsetX: startX,
                                text: t.base.string,
                                isSelected: state.selectedTextId == t.id,
                                pps: state.pixelsPerSecond,
                                onTap: {
                                    let was = (state.selectedTextId == t.id)
                                    state.selectedTextId = was ? nil : t.id
                                    if !was {
                                        state.selectedClipId = nil
                                        state.selectedAudioId = nil
                                        DispatchQueue.main.async { NotificationCenter.default.post(name: Notification.Name("OpenEditToolbarForSelection"), object: nil) }
                                    }
                                    didTapClip = true
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    if was { DispatchQueue.main.async { NotificationCenter.default.post(name: Notification.Name("CloseEditToolbarForDeselection"), object: nil) } }
                                },
                                onBeginMove: {
                                    if draggingTextId != t.id {
                                        draggingTextId = t.id
                                        textDragStartSeconds = max(0, CMTimeGetSeconds(t.start))
                                        isDraggingLaneItem = true
                                    }
                                },
                                onDragMove: { deltaSec in
                                    let proposed = textDragStartSeconds + deltaSec
                                    state.moveText(id: t.id, toStartSeconds: proposed)
                                },
                                onEndMove: { draggingTextId = nil; isDraggingLaneItem = false },
                                onTrimLeft: { dxSec in state.trimText(id: t.id, leftDeltaSeconds: dxSec) },
                                onTrimRight: { dxSec in state.trimText(id: t.id, rightDeltaSeconds: dxSec) }
                            )
                        }
                    }
                }

            Color.clear.frame(width: trailingInset, height: TimelineStyle.laneRowHeight)
        }
        .frame(height: TimelineStyle.laneRowHeight)
        .overlay(alignment: .topLeading) {
            if state.textOverlays.isEmpty {
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
    }
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                VStack(spacing: spacingAboveStrip) {
                    headerRuler(geo)
                    scrollerAndOverlays(geo)
                }

                // Centered playhead + HUD
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: playheadHeight)
                    .allowsHitTesting(false)
                if state.isScrubbing {
                    VStack(spacing: 4) {
                        Text(timeString(state.displayTime))
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(6)
                    }
                    .offset(y: -((stripHeight + spacingAboveStrip + rulerHeight + extraPlayheadExtension)/2) - 20)
                    .transition(.opacity)
                    .allowsHitTesting(false)
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
                Text("\(mmss(seconds(state.displayTime))) / \(mmss(seconds(state.duration)))")
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
            .onChange(of: state.displayTime) { _ in
                // Idle-only programmatic follow with modes
                guard !isScrollInteracting,
                      state.waitingForSeekCommit == false,
                      CACurrentMediaTime() - lastScrollEndedAt > 0.3,
                      CACurrentMediaTime() - lastZoomEndedAt > 0.25 else { return }
                let target = offsetForTime(state.displayTime, width: geo.size.width, pps: state.pixelsPerSecond)
                switch state.followMode {
                case .off:
                    break
                case .center:
                    // Always center the timeline under the fixed playhead during playback
                    if abs(target - observedOffsetX) > 0.5 { applyProgrammaticScroll(target) }
                case .keepVisible:
                    // Only scroll when the playhead would go offscreen
                    let leftEdge = observedOffsetX
                    let rightEdge = observedOffsetX + geo.size.width
                    let playheadX = leadingInset(for: geo.size.width) + CGFloat(seconds(state.displayTime)) * state.pixelsPerSecond
                    if playheadX < leftEdge || playheadX > rightEdge {
                        if abs(target - observedOffsetX) > 10 { applyProgrammaticScroll(target) }
                    }
                }
            }
            .onAppear {
                state.pixelsPerSecond = max(minPPS, min(maxPPS, state.pixelsPerSecond))
            }
            .gesture(magnifyGesture(geo: geo))
        }
        .frame(maxWidth: .infinity)
        .background(Color.editorTimelineBackground)
    }

    private func seconds(_ t: CMTime) -> Double { max(0.0, CMTimeGetSeconds(t)) }

    // One-shot programmatic scroll target. Sets programmaticX then clears next runloop.
    private func applyProgrammaticScroll(_ x: CGFloat) {
        programmaticX = x
        DispatchQueue.main.async { programmaticX = nil }
    }

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
                // Insert at current playhead (ripple), not append
                await MainActor.run {
                    Task { await state.insertClipAtPlayhead(url: dest) }
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
                let newPPS = max(minPPS, min(maxPPS, state.pixelsPerSecond * value))
                state.pixelsPerSecond = newPPS
                applyProgrammaticScroll(offsetForTime(state.displayTime, width: geo.size.width, pps: newPPS))
            }
            .onEnded { value in
                let newPPS = max(minPPS, min(maxPPS, state.pixelsPerSecond))
                state.pixelsPerSecond = newPPS
                applyProgrammaticScroll(offsetForTime(state.displayTime, width: geo.size.width, pps: newPPS))
                lastZoomEndedAt = CACurrentMediaTime()
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


