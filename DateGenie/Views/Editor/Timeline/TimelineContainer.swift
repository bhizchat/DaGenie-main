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
         onAddEnding: (() -> Void)? = nil,
         onPlusTapped: (() -> Void)? = nil) {
        self.state = state
        self.onAddAudio = onAddAudio
        self.onAddText = onAddText
        self.onAddEnding = onAddEnding
        self.onPlusTapped = onPlusTapped
    }

    // MARK: - Small helpers to tame type-checker in video row
    private func insertionGap() -> some View {
        RoundedRectangle(cornerRadius: 2)
            .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [5,3]))
            .background(Color.clear)
    }

    private func tileWidth(for clip: Clip) -> CGFloat {
        let raw = max(0, CMTimeGetSeconds(clip.duration))
        let end = CMTimeGetSeconds(clip.trimEnd ?? clip.duration)
        let start = CMTimeGetSeconds(clip.trimStart)
        let eff = max(0, min(raw, end) - max(0, start))
        return CGFloat(eff) * state.pixelsPerSecond
    }

    @ViewBuilder
    private func clipTile(clip: Clip,
                          index i: Int,
                          clipWidth: CGFloat,
                          starts: [CGFloat],
                          boundaries: [CGFloat],
                          leadingInset: CGFloat,
                          geoWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            if state.selectedClipId == clip.id && !state.isReorderMode {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white, lineWidth: 3)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                    .frame(width: clipWidth, height: TimelineStyle.videoRowHeight)
                    .offset(x: 0, y: 0)
                    .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1)
                    .zIndex(-1)
            }
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: clipWidth, height: TimelineStyle.videoRowHeight)
            if state.isReorderMode {
                let img = clip.thumbnails.first ?? UIImage()
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: clipWidth, height: TimelineStyle.videoRowHeight)
                    .clipped()
            } else {
                HStack(spacing: 0) {
                    let count = max(1, clip.thumbnails.count)
                    ForEach(0..<count, id: \.self) { j in
                        let img = j < clip.thumbnails.count ? clip.thumbnails[j] : UIImage()
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: max(24, state.pixelsPerSecond), height: TimelineStyle.videoRowHeight)
                            .clipped()
                    }
                }
                .frame(width: clipWidth, height: TimelineStyle.videoRowHeight, alignment: .leading)
                .clipped()
            }
            if state.selectedClipId == clip.id && !state.isReorderMode {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: clipWidth, height: 2)
                    .offset(y: (TimelineStyle.videoRowHeight / 2) - 1)
            }
        }
        .frame(width: clipWidth, height: TimelineStyle.videoRowHeight, alignment: .leading)
        .opacity(state.draggingClipId == clip.id ? 0.15 : 1.0)
        .offset(x: state.draggingClipId == clip.id ? state.dragTranslationX : 0,
                y: state.draggingClipId == clip.id ? -6 : 0)
        .contentShape(Rectangle())
        .zIndex(state.selectedClipId == clip.id ? 100 : 0)
        .onTapGesture {
            let wasSelected = (state.selectedClipId == clip.id)
            state.selectedClipId = wasSelected ? nil : clip.id
            if !wasSelected {
                state.selectedAudioId = nil
                state.selectedTextId = nil
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("OpenEditToolbarForSelection"), object: nil)
                }
            }
            didTapClip = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .modifier(InlineGestureModifier(gesture: {
            let press = LongPressGesture(minimumDuration: 0.18)
                .onEnded { _ in
                    state.beginClipReorderGesture(clipId: clip.id)
                    state.dragCandidateIndex = i
                    isDraggingLaneItem = true
                    selectionHaptics.prepare()
                }
            let drag = DragGesture(minimumDistance: 1, coordinateSpace: .named("timelineScroll"))
                .onChanged { value in
                    guard state.draggingClipId != nil else { return }
                    let originalCenter = (i < starts.count ? starts[i] : 0) + clipWidth * 0.5
                    let centerX = originalCenter + value.translation.width
                    var candidate = 0
                    for b in boundaries { if centerX >= b { candidate += 1 } }
                    candidate = max(0, min(candidate, state.clips.count))
                    if candidate != (state.dragCandidateIndex ?? -1) { selectionHaptics.selectionChanged() }
                    state.updateClipReorderGesture(candidateIndex: candidate, translationX: value.translation.width)
                    let itemCenterInContent = leadingInset + originalCenter + value.translation.width
                    let itemCenterInView = itemCenterInContent - observedOffsetX
                    updateAutoScroll(forHandleX: itemCenterInView, viewWidth: geoWidth)
                }
                .onEnded { _ in
                    isDraggingLaneItem = false
                    state.commitClipReorderGesture()
                    stopAutoScroll()
                }
            return press.sequenced(before: drag)
        }))
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
    // Single source of truth to vertically lift the entire timeline stack (ruler, rows, buttons, HUD)
    private let verticalLift: CGFloat = 80
    // Extend playhead/HUD upward; keep base consistent and add vertical lift so the HUD still clears the ruler
    private let basePlayheadExtension: CGFloat = 80
    private var extraPlayheadExtension: CGFloat { basePlayheadExtension + verticalLift }

    // Config
    private let minPPS: CGFloat = 20
    private let maxPPS: CGFloat = 300
    // Horizontal fine-tune so the first thumbnail sits relative to the playhead
    private let leftGap: CGFloat = 0.0
    // Horizontal nudge for empty-lane placeholders ("+ Add audio/text") to move the entire strip
    private let lanePlaceholderShiftX: CGFloat = 50

    // Hook to override plus behavior
    var onPlusTapped: (() -> Void)? = nil

    // Selection styling (CapCut-like)
    private let selectionPadH: CGFloat = 8
    private let selectionPadV: CGFloat = 6
    private let selectionHandleWidth: CGFloat = 24
    private let selectionHandleCorner: CGFloat = 0
    // Haptics for snapping
    private let selectionHaptics: UISelectionFeedbackGenerator = UISelectionFeedbackGenerator()
    // Snapshot state for text handle drags (stable math during gesture)
    private struct TextHandleSnapshot { let start: Double; let pps: CGFloat }
    @State private var textLeftSnapshot: TextHandleSnapshot? = nil
    @State private var textRightSnapshot: TextHandleSnapshot? = nil
    @State private var textLastSnapped: SnapTarget? = nil
    // Snapshot state for media overlay handle drags
    private struct MediaHandleSnapshot { let start: Double; let pps: CGFloat }
    @State private var mediaLeftSnapshot: MediaHandleSnapshot? = nil
    @State private var mediaRightSnapshot: MediaHandleSnapshot? = nil
    @State private var mediaLastSnapped: SnapTarget? = nil
    // Media drag helpers
    @State private var draggingMediaId: UUID? = nil
    @State private var mediaDragStartSeconds: Double = 0
    // Media move gesture (pickup → drag) helpers
    @GestureState private var mediaDragDX: CGFloat = 0
    @State private var mediaPickup: (start: Double, pps: CGFloat)? = nil
    @State private var mediaSnapHint: SnapTarget? = nil
    // Trim gating: keep handles non-blocking unless actively trimming
    @State private var isTrimming: Bool = false
    // Auto-scroll while trimming near edges
    @State private var autoScrollLink: CADisplayLink? = nil
    @State private var autoScrollDir: CGFloat = 0
    @State private var autoScrollStrength: CGFloat = 0
    @State private var autoScrollLastTS: CFTimeInterval = 0
    @State private var autoScrollEdgeEnteredAt: CFTimeInterval = 0
    private let autoScrollEdgeMin: CGFloat = 48
    private let autoScrollEdgeMax: CGFloat = 120
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
            .offset(y: headerOffsetY)
    }

    @ViewBuilder private func scrollerAndOverlays(_ geo: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            ScrollView(.horizontal, showsIndicators: false) {
                let showVertical = hasExtractedAudio || hasClip
                Group {
                    if showVertical {
                        // Include extracted audio lane when present so the text lane stays visible
                        let hasMediaOverlays = !state.mediaOverlays.isEmpty
                        let belowCount: CGFloat = 2 + (hasExtractedAudio ? 1 : 0) + (hasMediaOverlays ? 1 : 0)
                        let visibleHeight = TimelineStyle.videoRowHeight
                            + belowCount * TimelineStyle.laneRowHeight
                            + belowCount * TimelineStyle.rowSpacing
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: TimelineStyle.rowSpacing) {
                                videoRow(geo)
                                if hasExtractedAudio { extractedAudioRow(geo) }
                                if hasClip {
                                    extraAudioRow(geo)
                                    if hasMediaOverlays { mediaOverlayRow(geo) }
                                    textRow(geo)
                                }
                            }
                            .frame(height: stackedRowsHeight)
                            .background(VerticalScrollBridge { _, _, _, _ in })
                        }
                        .frame(height: visibleHeight)
                    } else {
                        VStack(spacing: TimelineStyle.rowSpacing) { videoRow(geo) }
                    }
                }
                .background(
                    ScrollViewBridge(targetX: programmaticX,
                                     isScrollEnabled: !(isDraggingLaneItem || state.isReorderMode)) { x, t, d, decel in
                        handleScrollEvent(x: x,
                                          isTracking: t,
                                          isDragging: d,
                                          isDecel: decel,
                                          geo: geo)
                    }
                )
                .scrollDisabled(isDraggingLaneItem || state.isReorderMode)
                // Keep overlay alignment coherent during programmatic follow while playing
                .onChange(of: state.displayTime) { _ in
                    if !isScrollInteracting {
                        observedOffsetX = offsetForTime(state.displayTime, width: geo.size.width, pps: state.pixelsPerSecond)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ResetTimelineDragGate"))) { _ in
                    if isDraggingLaneItem { isDraggingLaneItem = false }
                }
            }
            .coordinateSpace(name: "timelineScroll")
            .gesture(
                TapGesture().onEnded {
                    if !didTapClip {
                        state.selectedClipId = nil
                        state.selectedAudioId = nil
                        state.selectedTextId = nil
                        state.selectedMediaId = nil
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

                // Frame stroke should not intercept taps
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 3)
                    .frame(width: selW, height: TimelineStyle.videoRowHeight)
                    .position(x: startX + selW / 2,
                              y: TimelineStyle.videoRowHeight / 2)
                    .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1)
                    .allowsHitTesting(false)

                if !state.isPlaying {
                    // Left handle with snapping + auto-scroll + haptics
                    EdgeHandle(height: TimelineStyle.videoRowHeight,
                               width: selectionHandleWidth,
                               onDrag: { dx in
                                   let pps = state.pixelsPerSecond
                                   if !isDraggingLaneItem {
                                       isDraggingLaneItem = true
                                       isTrimming = true
                                       state.beginClipTrimGesture()
                                       selectionHaptics.prepare()
                                       leftHandlePrevDX = 0
                                   }
                                   let deltaSec = Double(dx / max(1, pps))
                                   let snapped = nearestSnap(to: s + deltaSec, pps: pps, excludeTextId: nil)
                                   if abs(Double(leftHandlePrevDX) / Double(max(1, pps)) - deltaSec) > 0.001, snapped.hit != nil {
                                       selectionHaptics.selectionChanged()
                                   }
                                   leftHandlePrevDX = dx
                                   if let cid = state.selectedClipId { state.trimClipDuringGesture(id: cid, leftDeltaSeconds: snapped.time - s) }
                                   updateAutoScroll(forHandleX: startX - selectionHandleWidth/2, viewWidth: geo.size.width)
                               },
                               onEnd: {
                                   leftHandlePrevDX = 0
                                   isDraggingLaneItem = false
                                   isTrimming = false
                                   Task { await state.endClipTrimGesture() }
                                   stopAutoScroll()
                               },
                               onBegin: nil,
                               onTap: { selectClipNeighbor(atEdgeTime: s, isRightEdge: false) })
                        .position(x: startX - selectionHandleWidth / 2,
                                  y: TimelineStyle.videoRowHeight / 2)
                        .zIndex(200)

                    // Right handle with snapping + auto-scroll + haptics
                    EdgeHandle(height: TimelineStyle.videoRowHeight,
                               width: selectionHandleWidth,
                               onDrag: { dx in
                                   let pps = state.pixelsPerSecond
                                   if !isDraggingLaneItem {
                                       isDraggingLaneItem = true
                                       isTrimming = true
                                       state.beginClipTrimGesture()
                                       selectionHaptics.prepare()
                                       rightHandlePrevDX = 0
                                   }
                                   let deltaSec = Double(dx / max(1, pps))
                                   let snapped = nearestSnap(to: e + deltaSec, pps: pps, excludeTextId: nil)
                                   if abs(Double(rightHandlePrevDX) / Double(max(1, pps)) - deltaSec) > 0.001, snapped.hit != nil {
                                       selectionHaptics.selectionChanged()
                                   }
                                   rightHandlePrevDX = dx
                                   if let cid = state.selectedClipId { state.trimClipDuringGesture(id: cid, rightDeltaSeconds: snapped.time - e) }
                                   updateAutoScroll(forHandleX: endX + selectionHandleWidth/2, viewWidth: geo.size.width)
                               },
                               onEnd: {
                                   rightHandlePrevDX = 0
                                   isDraggingLaneItem = false
                                   isTrimming = false
                                   Task { await state.endClipTrimGesture() }
                                   stopAutoScroll()
                               },
                               onBegin: nil,
                               onTap: { selectClipNeighbor(atEdgeTime: e, isRightEdge: true) })
                        .position(x: endX + selectionHandleWidth / 2,
                                  y: TimelineStyle.videoRowHeight / 2)
                        .zIndex(200)
                }
            }

            // Global overlay for AUDIO selection (absolute coordinates)
            if let sA = state.selectedAudioStartSeconds,
               let eA = state.selectedAudioEndSeconds,
               eA > sA, let a = state.selectedAudio {
                let pps = state.pixelsPerSecond
                let startX = (offsetForTime(CMTime(seconds: sA, preferredTimescale: 600), width: geo.size.width, pps: pps) + geo.size.width/2) - observedOffsetX
                let endX   = (offsetForTime(CMTime(seconds: eA, preferredTimescale: 600), width: geo.size.width, pps: pps) + geo.size.width/2) - observedOffsetX
                // Decide which audio lane Y to use (extracted vs regular). Extracted sits directly below video.
                let isExtractedSel = a.isExtracted
                // Offset to the center of the target lane
                let laneYOffset: CGFloat = {
                    if isExtractedSel {
                        return TimelineStyle.videoRowHeight + TimelineStyle.rowSpacing + (extractedLaneHeight / 2)
                    } else {
                        // If extracted lane exists, regular audio is one lane further down
                        let extra = hasExtractedAudio ? (extractedLaneHeight + TimelineStyle.rowSpacing) : 0
                        return TimelineStyle.videoRowHeight + TimelineStyle.rowSpacing + extra + (TimelineStyle.laneRowHeight / 2)
                    }
                }()
                let y = laneYOffset

                // Frame (optional outline to match video look)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: endX - startX, height: TimelineStyle.laneRowHeight)
                    .position(x: startX + (endX - startX)/2, y: y)
                    .allowsHitTesting(false)

                // Left handle — cumulative dx + snap-enter haptics + edge auto-scroll
                EdgeHandle(height: TimelineStyle.laneRowHeight, width: selectionHandleWidth, onDrag: { dx in
                    if !isDraggingLaneItem {
                        isDraggingLaneItem = true
                        isTrimming = true
                        state.beginAudioTrimGesture()
                        selectionHaptics.prepare()
                        // Reset prev to avoid stale buzz; we use cumulative dx model
                        leftHandlePrevDX = 0
                    }
                    let deltaSec = Double(dx / max(1, pps))
                    let proposedAbs = sA + deltaSec
                    let snapped = nearestSnap(to: proposedAbs, pps: pps, excludeTextId: nil)
                    if let _ = snapped.hit, leftHandlePrevDX == 0 { /* first snap prep done above */ }
                    // Fire a soft haptic only when the snapped absolute time changes meaningfully
                    // (simple edge: compare against last stored dx bucket)
                    if abs(Double(leftHandlePrevDX) / Double(max(1, pps)) - deltaSec) > 0.001, snapped.hit != nil {
                        selectionHaptics.selectionChanged()
                    }
                    leftHandlePrevDX = dx
                    state.trimAudioDuringGesture(id: a.id, leftDeltaSeconds: snapped.time - sA)
                    updateAutoScroll(forHandleX: startX - selectionHandleWidth/2, viewWidth: geo.size.width)
                }, onEnd: {
                    leftHandlePrevDX = 0
                    isDraggingLaneItem = false
                    isTrimming = false
                    state.endAudioTrimGesture()
                    stopAutoScroll()
                }, onBegin: nil, onTap: { selectAudioNeighbor(atEdgeTime: sA, isRightEdge: false, isExtracted: a.isExtracted) })
                .position(x: startX - selectionHandleWidth/2, y: y)
                .zIndex(220)
                .allowsHitTesting(isTrimming)
                .onDisappear { leftHandlePrevDX = 0 }

                // Right handle — cumulative dx + snap-enter haptics + edge auto-scroll
                EdgeHandle(height: TimelineStyle.laneRowHeight, width: selectionHandleWidth, onDrag: { dx in
                    if !isDraggingLaneItem {
                        isDraggingLaneItem = true
                        isTrimming = true
                        state.beginAudioTrimGesture()
                        selectionHaptics.prepare()
                        rightHandlePrevDX = 0
                    }
                    let deltaSec = Double(dx / max(1, pps))
                    let proposedAbs = eA + deltaSec
                    let snapped = nearestSnap(to: proposedAbs, pps: pps, excludeTextId: nil)
                    if abs(Double(rightHandlePrevDX) / Double(max(1, pps)) - deltaSec) > 0.001, snapped.hit != nil {
                        selectionHaptics.selectionChanged()
                    }
                    rightHandlePrevDX = dx
                    state.trimAudioDuringGesture(id: a.id, rightDeltaSeconds: snapped.time - eA)
                    updateAutoScroll(forHandleX: endX + selectionHandleWidth/2, viewWidth: geo.size.width)
                }, onEnd: {
                    rightHandlePrevDX = 0
                    isDraggingLaneItem = false
                    isTrimming = false
                    state.endAudioTrimGesture()
                    stopAutoScroll()
                }, onBegin: nil, onTap: { selectAudioNeighbor(atEdgeTime: eA, isRightEdge: true, isExtracted: a.isExtracted) })
                .position(x: endX + selectionHandleWidth/2, y: y)
                .zIndex(220)
                .allowsHitTesting(isTrimming)
                .onDisappear { rightHandlePrevDX = 0 }
            }

            // Global overlay for TEXT selection (absolute coordinates)
            if let sT = state.selectedTextStartSeconds,
               let eT = state.selectedTextEndSeconds,
               eT > sT, let t = state.selectedText {
                let pps = state.pixelsPerSecond
                let startX = (offsetForTime(CMTime(seconds: sT, preferredTimescale: 600), width: geo.size.width, pps: pps) + geo.size.width/2) - observedOffsetX
                let endX   = (offsetForTime(CMTime(seconds: eT, preferredTimescale: 600), width: geo.size.width, pps: pps) + geo.size.width/2) - observedOffsetX
                // If an extracted audio lane exists, the text lane is one row lower
                let extra = hasExtractedAudio ? (extractedLaneHeight + TimelineStyle.rowSpacing) : 0
                let y = TimelineStyle.videoRowHeight
                    + TimelineStyle.rowSpacing
                    + extra
                    + TimelineStyle.laneRowHeight
                    + TimelineStyle.rowSpacing
                    + (TimelineStyle.laneRowHeight / 2)
                // (Snapshots are declared at view scope)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: endX - startX, height: TimelineStyle.laneRowHeight)
                    .position(x: startX + (endX - startX)/2, y: y)
                    .allowsHitTesting(false)

                EdgeHandle(height: TimelineStyle.laneRowHeight, width: selectionHandleWidth, onDrag: { dx in
                    if !isDraggingLaneItem {
                        isDraggingLaneItem = true
                        isTrimming = true
                        state.beginTextTrimGesture()
                        selectionHaptics.prepare()
                        // capture baseline
                        let effStart = max(0, sT)
                        textLeftSnapshot = TextHandleSnapshot(start: effStart, pps: pps)
                        textLastSnapped = nil
                    }
                    let snapshotPPS = textLeftSnapshot?.pps ?? pps
                    let effStart = (textLeftSnapshot?.start ?? max(0, sT))
                    // Use cumulative translation (no prevDX)
                    let deltaSec = Double(dx / max(1, snapshotPPS))
                    let proposedAbs = effStart + deltaSec
                    var snapped = nearestSnap(to: proposedAbs, pps: snapshotPPS, excludeTextId: t.id)
                    // Frame-quantize the snapped time
                    snapped = (time: state.quantizeToFrame(snapped.time), hit: snapped.hit)
                    if let hit = snapped.hit, (textLastSnapped?.time != hit.time || textLastSnapped?.kind != hit.kind) {
                        selectionHaptics.selectionChanged()
                        textLastSnapped = hit
                    } else if snapped.hit == nil {
                        textLastSnapped = nil
                    }
                    let finalDelta = snapped.time - effStart
                    state.trimTextDuringGesture(id: t.id, leftDeltaSeconds: finalDelta)
                    // Edge auto-scroll
                    // Recompute live handle X using current timeline state
                    let liveStart = state.selectedTextStartSeconds ?? sT
                    let liveStartX = (offsetForTime(CMTime(seconds: liveStart, preferredTimescale: 600), width: geo.size.width, pps: pps) + geo.size.width/2) - observedOffsetX
                    updateAutoScroll(forHandleX: liveStartX - selectionHandleWidth/2, viewWidth: geo.size.width)
                }, onEnd: {
                    leftHandlePrevDX = 0
                    isDraggingLaneItem = false
                    isTrimming = false
                    textLeftSnapshot = nil
                    textLastSnapped = nil
                    state.endTextTrimGesture()
                    stopAutoScroll()
                }, onBegin: nil, onTap: { selectTextNeighbor(atEdgeTime: sT, isRightEdge: false) })
                .position(x: startX - selectionHandleWidth/2, y: y)
                .zIndex(220)
                .allowsHitTesting(isTrimming)
                .onDisappear { leftHandlePrevDX = 0; isDraggingLaneItem = false }

                EdgeHandle(height: TimelineStyle.laneRowHeight, width: selectionHandleWidth, onDrag: { dx in
                    if !isDraggingLaneItem {
                        isDraggingLaneItem = true
                        isTrimming = true
                        state.beginTextTrimGesture()
                        selectionHaptics.prepare()
                        let effEnd = max(0, eT)
                        textRightSnapshot = TextHandleSnapshot(start: effEnd, pps: pps)
                        textLastSnapped = nil
                    }
                    let snapshotPPS = textRightSnapshot?.pps ?? pps
                    let effEnd = (textRightSnapshot?.start ?? max(0, eT))
                    let deltaSec = Double(dx / max(1, snapshotPPS))
                    let proposedAbs = effEnd + deltaSec
                    var snapped = nearestSnap(to: proposedAbs, pps: snapshotPPS, excludeTextId: t.id)
                    snapped = (time: state.quantizeToFrame(snapped.time), hit: snapped.hit)
                    if let hit = snapped.hit, (textLastSnapped?.time != hit.time || textLastSnapped?.kind != hit.kind) {
                        selectionHaptics.selectionChanged()
                        textLastSnapped = hit
                    } else if snapped.hit == nil {
                        textLastSnapped = nil
                    }
                    let finalDelta = snapped.time - effEnd
                    state.trimTextDuringGesture(id: t.id, rightDeltaSeconds: finalDelta)
                    // Edge auto-scroll
                    let liveEnd = state.selectedTextEndSeconds ?? eT
                    let liveEndX = (offsetForTime(CMTime(seconds: liveEnd, preferredTimescale: 600), width: geo.size.width, pps: pps) + geo.size.width/2) - observedOffsetX
                    updateAutoScroll(forHandleX: liveEndX + selectionHandleWidth/2, viewWidth: geo.size.width)
                }, onEnd: {
                    rightHandlePrevDX = 0
                    isDraggingLaneItem = false
                    isTrimming = false
                    textRightSnapshot = nil
                    textLastSnapped = nil
                    state.endTextTrimGesture()
                    stopAutoScroll()
                }, onBegin: nil, onTap: { selectTextNeighbor(atEdgeTime: eT, isRightEdge: true) })
                .position(x: endX + selectionHandleWidth/2, y: y)
                .zIndex(220)
                .allowsHitTesting(isTrimming)
                .onDisappear { rightHandlePrevDX = 0; isDraggingLaneItem = false }
            }

            // Global overlay for MEDIA selection (absolute coordinates, mirrors TEXT)
            if let sM = state.selectedMediaStartSeconds,
               let eM = state.selectedMediaEndSeconds,
               eM > sM, let m = state.selectedMedia {
                let pps = state.pixelsPerSecond
                let startX = (offsetForTime(CMTime(seconds: sM, preferredTimescale: 600), width: geo.size.width, pps: pps) + geo.size.width/2) - observedOffsetX
                let endX   = (offsetForTime(CMTime(seconds: eM, preferredTimescale: 600), width: geo.size.width, pps: pps) + geo.size.width/2) - observedOffsetX
                // Media lane is above text lane when clips exist. If a clip exists, media lane sits between extra audio and text.
                let extra = hasExtractedAudio ? (extractedLaneHeight + TimelineStyle.rowSpacing) : 0
                let y = TimelineStyle.videoRowHeight
                    + TimelineStyle.rowSpacing
                    + extra
                    + TimelineStyle.laneRowHeight   // extraAudio row
                    + TimelineStyle.rowSpacing
                    + (TimelineStyle.laneRowHeight / 2) // media row center

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: endX - startX, height: TimelineStyle.laneRowHeight)
                    .position(x: startX + (endX - startX)/2, y: y)
                    .allowsHitTesting(false)

                EdgeHandle(height: TimelineStyle.laneRowHeight, width: selectionHandleWidth, onDrag: { dx in
                    if !isDraggingLaneItem {
                        isDraggingLaneItem = true
                        isTrimming = true
                        state.beginMediaTrimGesture()
                        selectionHaptics.prepare()
                        mediaLeftSnapshot = MediaHandleSnapshot(start: sM, pps: pps)
                        mediaLastSnapped = nil
                    }
                    let snapshotPPS = mediaLeftSnapshot?.pps ?? pps
                    let effStart = mediaLeftSnapshot?.start ?? sM
                    let deltaSec = Double(dx / max(1, snapshotPPS))
                    let proposedAbs = effStart + deltaSec
                    var snapped = nearestSnap(to: proposedAbs, pps: snapshotPPS, excludeTextId: nil)
                    snapped = (time: state.quantizeToFrame(snapped.time), hit: snapped.hit)
                    if let hit = snapped.hit, (mediaLastSnapped?.time != hit.time || mediaLastSnapped?.kind != hit.kind) {
                        selectionHaptics.selectionChanged(); mediaLastSnapped = hit
                    } else if snapped.hit == nil { mediaLastSnapped = nil }
                    state.trimMediaDuringGesture(id: m.id, leftDeltaSeconds: snapped.time - effStart)
                    // Edge auto-scroll (view-space x)
                    let liveStart = state.selectedMediaStartSeconds ?? sM
                    let liveStartX = (offsetForTime(CMTime(seconds: liveStart, preferredTimescale: 600), width: geo.size.width, pps: pps) + geo.size.width/2) - observedOffsetX
                    updateAutoScroll(forHandleX: liveStartX - selectionHandleWidth/2, viewWidth: geo.size.width)
                }, onEnd: {
                    isDraggingLaneItem = false
                    isTrimming = false
                    mediaLeftSnapshot = nil
                    mediaLastSnapped = nil
                    state.endMediaTrimGesture()
                    stopAutoScroll()
                }, onBegin: nil, onTap: { selectMediaNeighbor(atEdgeTime: sM, isRightEdge: false) })
                .position(x: startX - selectionHandleWidth/2, y: y)
                .zIndex(220)
                .allowsHitTesting(isTrimming)

                EdgeHandle(height: TimelineStyle.laneRowHeight, width: selectionHandleWidth, onDrag: { dx in
                    if !isDraggingLaneItem {
                        isDraggingLaneItem = true
                        isTrimming = true
                        state.beginMediaTrimGesture()
                        selectionHaptics.prepare()
                        mediaRightSnapshot = MediaHandleSnapshot(start: eM, pps: pps)
                        mediaLastSnapped = nil
                    }
                    let snapshotPPS = mediaRightSnapshot?.pps ?? pps
                    let effEnd = mediaRightSnapshot?.start ?? eM
                    let deltaSec = Double(dx / max(1, snapshotPPS))
                    let proposedAbs = effEnd + deltaSec
                    var snapped = nearestSnap(to: proposedAbs, pps: snapshotPPS, excludeTextId: nil)
                    snapped = (time: state.quantizeToFrame(snapped.time), hit: snapped.hit)
                    if let hit = snapped.hit, (mediaLastSnapped?.time != hit.time || mediaLastSnapped?.kind != hit.kind) {
                        selectionHaptics.selectionChanged(); mediaLastSnapped = hit
                    } else if snapped.hit == nil { mediaLastSnapped = nil }
                    state.trimMediaDuringGesture(id: m.id, rightDeltaSeconds: snapped.time - effEnd)
                    let liveEnd = state.selectedMediaEndSeconds ?? eM
                    let liveEndX = (offsetForTime(CMTime(seconds: liveEnd, preferredTimescale: 600), width: geo.size.width, pps: pps) + geo.size.width/2) - observedOffsetX
                    updateAutoScroll(forHandleX: liveEndX + selectionHandleWidth/2, viewWidth: geo.size.width)
                }, onEnd: {
                    isDraggingLaneItem = false
                    isTrimming = false
                    mediaRightSnapshot = nil
                    mediaLastSnapped = nil
                    state.endMediaTrimGesture()
                    stopAutoScroll()
                }, onBegin: nil, onTap: { selectMediaNeighbor(atEdgeTime: eM, isRightEdge: true) })
                .position(x: endX + selectionHandleWidth/2, y: y)
                .zIndex(220)
                .allowsHitTesting(isTrimming)
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
        let onTap: (() -> Void)?
        @GestureState private var dx: CGFloat = 0
        @State private var didBegin: Bool = false
        @State private var maxAbsTranslation: CGFloat = 0
        init(height: CGFloat,
             width: CGFloat,
             onDrag: @escaping (CGFloat) -> Void,
             onEnd: @escaping () -> Void,
             onBegin: (() -> Void)? = nil,
             onTap: (() -> Void)? = nil) {
            self.height = height
            self.width = width
            self.onDrag = onDrag
            self.onEnd = onEnd
            self.onBegin = onBegin
            self.onTap = onTap
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
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .updating($dx) { v, st, _ in st = v.translation.width }
                    .onChanged { v in
                        if !didBegin { didBegin = true; onBegin?() }
                        maxAbsTranslation = max(maxAbsTranslation, abs(v.translation.width))
                        onDrag(v.translation.width)
                    }
                    .onEnded { _ in
                        // Treat a very small translation as a tap to enable neighbor selection
                        if maxAbsTranslation < 6 { onTap?() }
                        maxAbsTranslation = 0
                        didBegin = false
                        onEnd()
                    }
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
            .simultaneousGesture(DragGesture(minimumDistance: 8)) // allow normal scroll when user drags without long-press
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
                .simultaneousGesture(DragGesture(minimumDistance: 8))
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
        -((stripHeight + spacingAboveStrip + rulerHeight)/2) - 10 - 50 - verticalLift
    }

    // Shared rows vertical offset used by both the ScrollView rows and the selection overlay
    private var rowsOffsetY: CGFloat {
        -((stripHeight + spacingAboveStrip + rulerHeight)/2) - 10 - 50 - verticalLift
    }

    // Fixed container height for the stacked rows to prevent layout jumps when overlay appears
    private var rowsStackHeight: CGFloat {
        let lanesCount: CGFloat = hasClip ? 2 : 0
        return TimelineStyle.videoRowHeight
             + lanesCount * TimelineStyle.laneRowHeight
             + lanesCount * TimelineStyle.rowSpacing
             + extractedExtraHeight
    }

    // Extend playhead to span video + all timeline lanes below
    private var playheadHeight: CGFloat {
        return rulerHeight + spacingAboveStrip + stackedRowsHeight + extraPlayheadExtension
    }

    private var hasClip: Bool {
        !state.clips.isEmpty && CMTimeGetSeconds(state.totalDuration) > 0
    }

    // Computed rows height used for layout and publishing preferred height
    private var lanesCount: CGFloat {
        // When overlays exist, include an extra lane row to reserve vertical space
        let hasMediaOverlays = !state.mediaOverlays.isEmpty
        return (hasClip ? 2 : 0) + (hasMediaOverlays ? 1 : 0)
    }
    private var stackedRowsHeight: CGFloat {
        TimelineStyle.videoRowHeight
        + lanesCount * TimelineStyle.laneRowHeight
        + lanesCount * TimelineStyle.rowSpacing
        + extractedExtraHeight
    }
    private var preferredHeight: CGFloat {
        rulerHeight + spacingAboveStrip + stackedRowsHeight
    }

    // Centralized vertical anchors so both states (no-clip/has-clip) align consistently
    private var rowsBaseY: CGFloat { -((stripHeight + spacingAboveStrip + rulerHeight)/2) - 10 - 50 - verticalLift }
    private var filmstripCenterY: CGFloat { rowsBaseY + (TimelineStyle.videoRowHeight / 2) }
    private var noClipButtonDelta: CGFloat { hasClip ? 0 : 120 }
    private var clipButtonDelta: CGFloat { hasClip ? 80 : 0 }
    private var audioButtonCenterY: CGFloat { (filmstripCenterY - 26) + noClipButtonDelta + clipButtonDelta - 15 }
    private var textButtonCenterY: CGFloat { (filmstripCenterY + 26) + noClipButtonDelta + clipButtonDelta - 15 }

    

    // MARK: - Rows (split out for compiler)
    @ViewBuilder private func videoRow(_ geo: GeometryProxy) -> some View {
        // Break sub-expressions into smaller computed lets to aid type-checker.
        let viewWidth = geo.size.width
        let pps = state.pixelsPerSecond
        HStack(spacing: 0) {
            // Compute compact centering for square-tile reorder mode so tiles gather under playhead
            let compactTotalWidth: CGFloat = {
                guard state.isReorderMode else { return 0 }
                let tiles = CGFloat(state.clips.count) * state.reorderTileSide
                let gaps = CGFloat(max(0, state.clips.count - 1)) * state.reorderTileSpacing
                return tiles + gaps
            }()
            let leadingInset: CGFloat = {
                if state.isReorderMode {
                    return max(0, ((viewWidth - compactTotalWidth) / 2) + leftGap)
                } else {
                    return max(0, (viewWidth / 2) + leftGap)
                }
            }()
            let trailingInset: CGFloat = {
                if state.isReorderMode {
                    return max(0, ((viewWidth - compactTotalWidth) / 2) - leftGap)
                } else {
                    return max(0, (viewWidth / 2) - leftGap)
                }
            }()
            // Precompute timeline metrics (widths and cumulative starts in points)
            // In reorder mode, use uniform square tiles plus spacing; otherwise use filmstrip widths
            let widths: [CGFloat] = state.isReorderMode ? Array(repeating: state.reorderTileSide + state.reorderTileSpacing, count: state.clips.count) : state.clips.map { c in
                let rawSeconds = max(0, CMTimeGetSeconds(c.duration))
                let trimmedEnd = CMTimeGetSeconds(c.trimEnd ?? c.duration)
                let trimmedStart = CMTimeGetSeconds(c.trimStart)
                let eff = max(0, min(rawSeconds, trimmedEnd) - max(0, trimmedStart))
                return CGFloat(eff) * pps
            }
            // Cumulative left edges computed functionally to satisfy ViewBuilder constraints
            let starts: [CGFloat] = widths.indices.map { i in
                widths.prefix(i).reduce(CGFloat(0), +)
            }
            let boundaries: [CGFloat] = Array(starts.dropFirst())
            Color.clear.frame(width: leadingInset, height: TimelineStyle.videoRowHeight)
            ForEach(Array(state.clips.enumerated()), id: \.element.id) { i, clip in
                // Placeholder gap before tile at current candidate insert index (including original)
                if state.isReorderMode, state.dragCandidateIndex == i {
                    insertionGap()
                        .frame(width: state.reorderTileSpacing, height: TimelineStyle.videoRowHeight)
                }
                let clipWidth = state.isReorderMode ? state.reorderTileSide : tileWidth(for: clip)
                clipTile(clip: clip,
                         index: i,
                         clipWidth: clipWidth,
                         starts: starts,
                         boundaries: boundaries,
                         leadingInset: leadingInset,
                         geoWidth: geo.size.width)
                // Add consistent spacing between square tiles in reorder mode (except where the insertion gap is shown)
                if state.isReorderMode {
                    let isLast = (i == state.clips.count - 1)
                    let nextIndex = i + 1
                    let shouldAddSpacing = !isLast && (state.dragCandidateIndex != nextIndex)
                    if shouldAddSpacing {
                        Color.clear.frame(width: state.reorderTileSpacing, height: TimelineStyle.videoRowHeight)
                    }
                }
            }
            // If candidate is the very end, render a trailing placeholder before the trailing inset
            if state.isReorderMode, state.dragCandidateIndex == state.clips.count {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: state.reorderTileSpacing, height: TimelineStyle.videoRowHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [5,3]))
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
                    if !state.audioTracks.contains(where: { !$0.isExtracted }) {
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
                        ForEach(Array(state.audioTracks.enumerated()).filter { !$0.element.isExtracted }, id: \.element.id) { _, t in
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
            if !state.audioTracks.contains(where: { !$0.isExtracted }) {
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
                let baseY = -((stripHeight + spacingAboveStrip + rulerHeight)/2) - 10 - 50 - verticalLift
                // Push the plus button down by an additional ~15pt
                let plusY = baseY + (TimelineStyle.videoRowHeight / 2) + (hasClip ? -10 : 20) + 15
                Button(action: { onPlusTapped?() }) {
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
                    .offset(y: -verticalLift) // moved down by ~10pt
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

    // MARK: - Extracted audio lane helpers
    private var hasExtractedAudio: Bool {
        state.audioTracks.contains { $0.isExtracted }
    }
    private var extractedLaneHeight: CGFloat { TimelineStyle.laneRowHeight }
    private var extractedExtraHeight: CGFloat {
        hasExtractedAudio ? (extractedLaneHeight + TimelineStyle.rowSpacing) : 0
    }

    @ViewBuilder private func extractedAudioRow(_ geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            let center = geo.size.width / 2
            let leadingInset = max(0, center + leftGap)
            let trailingInset = max(0, center - leftGap)
            let totalSeconds = max(0, CMTimeGetSeconds(state.totalDuration))
            let timelineWidth = CGFloat(totalSeconds) * state.pixelsPerSecond

            Color.clear.frame(width: leadingInset, height: extractedLaneHeight)

            Rectangle().fill(Color.clear)
                .frame(width: timelineWidth, height: extractedLaneHeight)
                .overlay(alignment: .topLeading) {
                    ForEach(state.audioTracks.filter { $0.isExtracted }, id: \.id) { t in
                        let startX: CGFloat = CGFloat(max(0, CMTimeGetSeconds(t.start + t.trimStart))) * state.pixelsPerSecond
                        let width: CGFloat = CGFloat(max(0, CMTimeGetSeconds(t.trimmedDuration))) * state.pixelsPerSecond
                        ExtractedAudioStrip(width: width,
                                            height: extractedLaneHeight,
                                            offsetX: startX,
                                            title: t.displayName,
                                            samples: t.waveformSamples,
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
                                            })
                    }
                }

            Color.clear.frame(width: trailingInset, height: extractedLaneHeight)
        }
        .frame(height: extractedLaneHeight)
    }

    private struct ExtractedAudioStrip: View {
        let width: CGFloat
        let height: CGFloat
        let offsetX: CGFloat
        let title: String
        let samples: [Float]
        let onTap: () -> Void
        var body: some View {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0xBE/255.0, green: 0x93/255.0, blue: 0xD4/255.0, opacity: 0.9))
                WaveformView(samples: samples, color: Color.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.top, 4)
                    .padding(.leading, 6)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
            )
            .offset(x: offsetX)
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded { onTap() })
        }
    }

    private func seconds(_ t: CMTime) -> Double { max(0.0, CMTimeGetSeconds(t)) }

    // One-shot programmatic scroll target. Sets programmaticX then clears next runloop.
    private func applyProgrammaticScroll(_ x: CGFloat) {
        let clamped = max(0, x)
        // Keep overlay math in lockstep with programmatic scroll
        observedOffsetX = clamped
        programmaticX = clamped
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

    // MARK: - Media Overlay Row (appears only when overlays exist)
    @ViewBuilder
    private func mediaOverlayRow(_ geo: GeometryProxy) -> some View {
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
                    ForEach(Array(state.mediaOverlays.enumerated()), id: \.element.id) { _, m in
                        let pps: CGFloat = state.pixelsPerSecond
                        let s: Double = max(0, CMTimeGetSeconds(m.effectiveStart))
                        let w: Double = max(0, CMTimeGetSeconds(m.trimmedDuration))
                        let startX: CGFloat = CGFloat(s) * pps
                        let width: CGFloat  = CGFloat(w) * pps
                        mediaPill(m: m, s: s, width: width, startX: startX, pps: pps, geo: geo)
                        // Trim handles for media are rendered in the global overlay below (consistent with text)
                    }
                }

            Color.clear.frame(width: trailingInset, height: TimelineStyle.laneRowHeight)
        }
        .frame(height: TimelineStyle.laneRowHeight)
    }

    private func dragGesture(geo: GeometryProxy) -> some Gesture {
        // Deprecated: let UIScrollView own horizontal pan; we keep function to avoid breaking calls
        DragGesture(minimumDistance: 1)
            .onChanged { _ in }
            .onEnded { _ in }
    }

    private func magnifyGesture(geo: GeometryProxy) -> some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.01)
            .updating($pinchScale) { value, scale, _ in
                guard !isDraggingLaneItem else { return }
                scale = value
                let newPPS = max(minPPS, min(maxPPS, state.pixelsPerSecond * value))
                state.pixelsPerSecond = newPPS
                applyProgrammaticScroll(offsetForTime(state.displayTime, width: geo.size.width, pps: newPPS))
            }
            .onEnded { value in
                guard !isDraggingLaneItem else { return }
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

// Helper to attach a highPriorityGesture produced inline (workaround for `some Gesture` constraint in modifiers)
private struct InlineGestureModifier<G: Gesture>: ViewModifier {
    let gestureProvider: () -> G
    init(gesture: @escaping () -> G) { self.gestureProvider = gesture }
    func body(content: Content) -> some View {
        content.highPriorityGesture(gestureProvider(), including: .gesture)
    }
}

// MARK: - Media overlay pill helpers (extracted to reduce type-check depth)
private extension TimelineContainer {
    @ViewBuilder
    func mediaPill(m: TimedMediaOverlay,
                   s: Double,
                   width: CGFloat,
                   startX: CGFloat,
                   pps: CGFloat,
                   geo: GeometryProxy) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.green.opacity(0.18))
            .frame(width: max(12, width), height: TimelineStyle.laneRowHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(state.selectedMediaId == m.id ? Color.white : Color.clear, lineWidth: 2)
            )
            .offset(x: startX)
            .contentShape(Rectangle())
            .gesture(TapGesture().onEnded { handleMediaTap(m.id) })
            .highPriorityGesture(mediaMoveGesture(for: m, startSeconds: s, pps: pps, geo: geo))
    }

    func handleMediaTap(_ id: UUID) {
        let was = (state.selectedMediaId == id)
        state.selectedMediaId = was ? nil : id
        if !was {
            state.selectedClipId = nil
            state.selectedAudioId = nil
            state.selectedTextId = nil
            DispatchQueue.main.async { NotificationCenter.default.post(name: Notification.Name("OpenEditToolbarForSelection"), object: nil) }
        } else {
            DispatchQueue.main.async { NotificationCenter.default.post(name: Notification.Name("CloseEditToolbarForDeselection"), object: nil) }
        }
        didTapClip = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func mediaMoveGesture(for m: TimedMediaOverlay,
                          startSeconds s: Double,
                          pps: CGFloat,
                          geo: GeometryProxy) -> AnyGesture<Void> {
        let pickup = LongPressGesture(minimumDuration: 0.18)
        let drag = DragGesture(minimumDistance: 0, coordinateSpace: .named("timelineScroll"))
            .updating($mediaDragDX) { v, st, _ in st = v.translation.width }
            .onChanged { v in handleMediaMoveChanged(v, start: s, pps: pps, id: m.id, geo: geo) }
            .onEnded { v in handleMediaMoveEnded(v, start: s, pps: pps, id: m.id) }
        let seq = pickup.sequenced(before: drag).map { _ in () }
        return AnyGesture(seq)
    }

    func handleMediaMoveChanged(_ v: DragGesture.Value,
                                start s: Double,
                                pps: CGFloat,
                                id: UUID,
                                geo: GeometryProxy) {
        if mediaPickup == nil {
            mediaPickup = (start: s, pps: pps)
            isDraggingLaneItem = true
            state.selectedMediaId = id
            state.selectedClipId = nil
            state.selectedAudioId = nil
            state.selectedTextId = nil
        }
        guard let pu = mediaPickup else { return }
        let dx: CGFloat = v.translation.width
        let invPPS: CGFloat = 1 / max(1, pu.pps)
        let proposed: Double = pu.start + Double(dx * invPPS)
        withAnimation(nil) {
            state.moveMedia(id: id, toStartSeconds: proposed)
        }
        // Snap hint
        let snap = nearestSnap(to: proposed, pps: pu.pps, excludeTextId: nil)
        if let hit = snap.hit {
            if hit.time != mediaSnapHint?.time || hit.kind != mediaSnapHint?.kind {
                selectionHaptics.selectionChanged()
                mediaSnapHint = hit
            }
        } else {
            mediaSnapHint = nil
        }
        // Edge auto-scroll
        let ox: CGFloat = offsetForTime(CMTime(seconds: proposed, preferredTimescale: 600), width: geo.size.width, pps: pu.pps)
        let itemX: CGFloat = (ox + geo.size.width/2) - observedOffsetX
        updateAutoScroll(forHandleX: itemX, viewWidth: geo.size.width)
    }

    func handleMediaMoveEnded(_ v: DragGesture.Value,
                              start s: Double,
                              pps: CGFloat,
                              id: UUID) {
        let pu = mediaPickup ?? (start: s, pps: pps)
        let dx: CGFloat = v.translation.width
        let invPPS: CGFloat = 1 / max(1, pu.pps)
        let proposed: Double = pu.start + Double(dx * invPPS)
        let snapped = nearestSnap(to: proposed, pps: pu.pps, excludeTextId: nil)
        withAnimation(nil) {
            state.moveMedia(id: id, toStartSeconds: state.quantizeToFrame(snapped.time))
        }
        mediaPickup = nil
        mediaSnapHint = nil
        draggingMediaId = nil
        isDraggingLaneItem = false
        stopAutoScroll()
    }
}

// MARK: - ScrollView content offset bridging
// MARK: - Snapping helpers
private struct SnapTarget: Hashable {
    enum Kind: Hashable { case playhead, second, itemEdge }
    let time: Double
    let kind: Kind
}

private extension TimelineContainer {
    /// Compute nearest snap in seconds given a proposed absolute time.
    /// Tolerance is points-based (~12pt) converted to seconds via current PPS.
    func nearestSnap(to proposed: Double, pps: CGFloat, excludeTextId: UUID?) -> (time: Double, hit: SnapTarget?) {
        let pxThreshold: CGFloat = 12
        let tol = Double(pxThreshold / max(1, pps))
        var anchors: [SnapTarget] = []
        // Playhead
        anchors.append(SnapTarget(time: max(0, CMTimeGetSeconds(state.displayTime)), kind: .playhead))
        // Neighbor text edges
        for t in state.textOverlays where t.id != excludeTextId {
            let s = max(0, CMTimeGetSeconds(t.effectiveStart))
            let e = s + max(0, CMTimeGetSeconds(t.trimmedDuration))
            anchors.append(SnapTarget(time: s, kind: .itemEdge))
            anchors.append(SnapTarget(time: e, kind: .itemEdge))
        }
        // Neighbor media overlay edges
        for m in state.mediaOverlays {
            let s = max(0, CMTimeGetSeconds(m.effectiveStart))
            let e = s + max(0, CMTimeGetSeconds(m.trimmedDuration))
            anchors.append(SnapTarget(time: s, kind: .itemEdge))
            anchors.append(SnapTarget(time: e, kind: .itemEdge))
        }
        // Video clip edges
        for c in state.clips {
            let s = max(0, state.startSeconds(for: c.id) ?? 0)
            let e = s + max(0, CMTimeGetSeconds(c.trimmedDuration))
            anchors.append(SnapTarget(time: s, kind: .itemEdge))
            anchors.append(SnapTarget(time: e, kind: .itemEdge))
        }
        // Whole seconds around proposed
        let base = floor(proposed)
        // Quantize second marks to frame boundaries to avoid near-second jitter
        let sec0 = state.quantizeToFrame(base)
        let sec1 = state.quantizeToFrame(base + 1)
        anchors.append(SnapTarget(time: sec0, kind: .second))
        anchors.append(SnapTarget(time: sec1, kind: .second))
        // Project tail as a snap target
        anchors.append(SnapTarget(time: max(0, CMTimeGetSeconds(state.totalDuration)), kind: .itemEdge))
        // Find nearest within tolerance
        var best: (SnapTarget, Double)? = nil
        for a in anchors {
            let d = abs(a.time - proposed)
            if d <= tol && (best == nil || d < best!.1) { best = (a, d) }
        }
        if let (hit, _) = best { return (hit.time, hit) }
        return (proposed, nil)
    }

    // MARK: - Neighbor selection helpers (enable tapping handles to select adjacent items)
    private func approximatelyEquals(_ a: Double, _ b: Double, tol: Double = 1.0/300.0) -> Bool {
        abs(a - b) <= tol
    }

    private func selectClipNeighbor(atEdgeTime edge: Double, isRightEdge: Bool) {
        let edgeQ = state.quantizeToFrame(edge)
        if isRightEdge {
            // Next clip whose start equals current end
            if let next = state.clips.first(where: { c in
                let s = state.startSeconds(for: c.id) ?? 0
                return approximatelyEquals(state.quantizeToFrame(s), edgeQ)
            }) {
                state.selectedClipId = next.id
                state.selectedAudioId = nil; state.selectedTextId = nil; state.selectedMediaId = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } else {
            // Previous clip whose end equals current start
            if let prev = state.clips.first(where: { c in
                let s = state.startSeconds(for: c.id) ?? 0
                let e = s + max(0, CMTimeGetSeconds(c.trimmedDuration))
                return approximatelyEquals(state.quantizeToFrame(e), edgeQ)
            }) {
                state.selectedClipId = prev.id
                state.selectedAudioId = nil; state.selectedTextId = nil; state.selectedMediaId = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func selectTextNeighbor(atEdgeTime edge: Double, isRightEdge: Bool) {
        let edgeQ = state.quantizeToFrame(edge)
        if isRightEdge {
            if let n = state.textOverlays.first(where: { t in
                let s = max(0, CMTimeGetSeconds(t.effectiveStart))
                return approximatelyEquals(state.quantizeToFrame(s), edgeQ)
            }) {
                state.selectedTextId = n.id
                state.selectedClipId = nil; state.selectedAudioId = nil; state.selectedMediaId = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } else {
            if let p = state.textOverlays.first(where: { t in
                let s = max(0, CMTimeGetSeconds(t.effectiveStart))
                let e = s + max(0, CMTimeGetSeconds(t.trimmedDuration))
                return approximatelyEquals(state.quantizeToFrame(e), edgeQ)
            }) {
                state.selectedTextId = p.id
                state.selectedClipId = nil; state.selectedAudioId = nil; state.selectedMediaId = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func selectMediaNeighbor(atEdgeTime edge: Double, isRightEdge: Bool) {
        let edgeQ = state.quantizeToFrame(edge)
        if isRightEdge {
            if let n = state.mediaOverlays.first(where: { m in
                let s = max(0, CMTimeGetSeconds(m.effectiveStart))
                return approximatelyEquals(state.quantizeToFrame(s), edgeQ)
            }) {
                state.selectedMediaId = n.id
                state.selectedClipId = nil; state.selectedAudioId = nil; state.selectedTextId = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } else {
            if let p = state.mediaOverlays.first(where: { m in
                let s = max(0, CMTimeGetSeconds(m.effectiveStart))
                let e = s + max(0, CMTimeGetSeconds(m.trimmedDuration))
                return approximatelyEquals(state.quantizeToFrame(e), edgeQ)
            }) {
                state.selectedMediaId = p.id
                state.selectedClipId = nil; state.selectedAudioId = nil; state.selectedTextId = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func selectAudioNeighbor(atEdgeTime edge: Double, isRightEdge: Bool, isExtracted: Bool) {
        let edgeQ = state.quantizeToFrame(edge)
        let tracks = state.audioTracks.filter { $0.isExtracted == isExtracted }
        if isRightEdge {
            if let n = tracks.first(where: { t in
                let s = max(0, CMTimeGetSeconds(t.start + t.trimStart))
                return approximatelyEquals(state.quantizeToFrame(s), edgeQ)
            }) {
                state.selectedAudioId = n.id
                state.selectedClipId = nil; state.selectedTextId = nil; state.selectedMediaId = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } else {
            if let p = tracks.first(where: { t in
                let s = max(0, CMTimeGetSeconds(t.start + t.trimStart))
                let e = s + max(0, CMTimeGetSeconds(t.trimmedDuration))
                return approximatelyEquals(state.quantizeToFrame(e), edgeQ)
            }) {
                state.selectedAudioId = p.id
                state.selectedClipId = nil; state.selectedTextId = nil; state.selectedMediaId = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    // MARK: - Auto-scroll helpers
    private func currentEdgeThreshold(for viewWidth: CGFloat) -> CGFloat {
        // Scale edge zone with zoom (pps) and clamp to sensible touch sizes
        let z = max(0, min(1, (state.pixelsPerSecond - minPPS) / max(1, (maxPPS - minPPS))))
        return autoScrollEdgeMin + (autoScrollEdgeMax - autoScrollEdgeMin) * z
    }

    private func startAutoScroll(direction: CGFloat, strength: CGFloat) {
        autoScrollDir = direction
        autoScrollStrength = max(0, min(1, strength))
        if autoScrollLink == nil {
            let link = CADisplayLink(target: AutoScrollProxy { l in self.tickAutoScroll(l) }, selector: #selector(AutoScrollProxy.tick(_:)))
            link.preferredFramesPerSecond = 0
            link.add(to: .main, forMode: .common)
            autoScrollLink = link
            autoScrollLastTS = 0
            autoScrollEdgeEnteredAt = CACurrentMediaTime()
        }
    }

    private func stopAutoScroll() {
        autoScrollLink?.invalidate()
        autoScrollLink = nil
        autoScrollDir = 0
        autoScrollStrength = 0
        autoScrollLastTS = 0
        autoScrollEdgeEnteredAt = 0
    }

    private func updateAutoScroll(forHandleX handleXInView: CGFloat, viewWidth: CGFloat) {
        let edge = currentEdgeThreshold(for: viewWidth)
        let leftDist  = handleXInView
        let rightDist = viewWidth - handleXInView
        if leftDist < edge {
            let s = 1 - max(0, leftDist / edge)
            if autoScrollDir != -1 { autoScrollEdgeEnteredAt = CACurrentMediaTime() }
            startAutoScroll(direction: -1, strength: s)
        } else if rightDist < edge {
            let s = 1 - max(0, rightDist / edge)
            if autoScrollDir != +1 { autoScrollEdgeEnteredAt = CACurrentMediaTime() }
            startAutoScroll(direction: +1, strength: s)
        } else {
            stopAutoScroll()
        }
    }

    private func tickAutoScroll(_ link: CADisplayLink) {
        guard autoScrollDir != 0 else { return }
        let now = link.timestamp
        let dt = (autoScrollLastTS == 0) ? link.duration : now - autoScrollLastTS
        autoScrollLastTS = now

        // cubic ease near the edge + dwell ramp
        let prox = max(0, min(1, autoScrollStrength))
        let eased = prox * prox * prox
        let dwell = min(1.0, max(0.0, (now - autoScrollEdgeEnteredAt) / 0.75))
        let dwellBoost: CGFloat = 1.0 + dwell

        // seconds/sec mapped to px/sec using current zoom
        let secPerSec: CGFloat = 1.5 + (8.0 - 1.5) * eased
        let pxPerSec: CGFloat  = secPerSec * state.pixelsPerSecond * dwellBoost
        let dx = autoScrollDir * pxPerSec * CGFloat(dt)
        applyProgrammaticScroll(observedOffsetX + dx)
    }
}

private final class AutoScrollProxy: NSObject {
    let handler: (CADisplayLink) -> Void
    init(_ h: @escaping (CADisplayLink) -> Void) { handler = h }
    @objc func tick(_ l: CADisplayLink) { handler(l) }
}

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
                    // Reduce friction while programmatically scrolling during trims
                    scrollView.decelerationRate = .fast
                    scrollView.bounces = false
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


