//  AdventureMapView.swift
//  DateGenie
//
//  Stylised progress map shown after user accepts 5 themes.
//  Inspired by Figma design – stacked red circles with star icons.
//
import SwiftUI

struct AdventureMapView: View {
    // MARK: - Input
    let themes: [CampusTheme]      // accepted themes (max 5)
    let level: Int                 // Currently always 1

    // MARK: - Env
    @Environment(\.dismiss) private var dismiss

    // MARK: - State
    @State private var completed = 0
    @State private var showGame = false
    @State private var selectedIdx = 0
    // Removed countdown timer per new simplified UI
    @State private var showQuitAlert = false
    @State private var perMissionSteps: [Int: Set<JourneyStep>] = [:]
    // Read-only replay state (for Journey)
    var isReadOnly: Bool = false
    var replayRunId: String? = nil
    // Templates for Game-to-Play intro by node index (use venue then punishment)
    private let gameIntroTemplates: [String] = [
        "Kick off your adventure at %@! Warm up by playing 3 rounds of Rock, Paper and Scissors with your partner. %@  Record every laugh with the camera—once filming finishes, your status will automatically mark this checkpoint complete.",
        "Great start! Head over to %@ for Round 2. Challenge your partner to 3 fresh games of Rock, Paper and Scissors. %@  Capture the fun on camera; when filming wraps, this checkpoint will complete and the journey continues.",
        "You’re halfway there! At %@, launch straight into 3 decisive rounds of Rock, Paper and Scissors. %@  Film the antics—after recording, your status will flip to complete and the next task will unlock.",
        "Almost at the finish line. Drop by %@ and put your Rock, Paper and Scissors skills to the test with another best-of-3. %@  Snap those hilarious moments; recording automatically completes this checkpoint, pushing you to the final challenge.",
        "Final showdown! Meet at %@ for your last 3 rounds of Rock, Paper and Scissors. %@  Record the epic finale with the camera; once filming ends and the status completes, celebrate finishing the adventure in style."
    ]

    // MARK: - Body
    var body: some View {
        VStack {
            header
            Spacer(minLength: 24)
            pathStars
            Spacer()
            generateReelButton
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            let level = LevelStore.shared.currentLevel
            if !isReadOnly {
                // Ensure we have a run for this level and restore completion count
                if RunManager.shared.currentRunId == nil {
                    _ = RunManager.shared.resumeLastRun(level: level)
                    if RunManager.shared.currentRunId == nil {
                        _ = RunManager.shared.startNewRun(level: level)
                        JourneyPersistence.shared.saveLevelHeader(level: level)
                        print("[AdventureMapView] started new runId for level: \(level)")
                    }
                }
            }
            // Load step presence to compute points accurately
            if let runId = isReadOnly ? replayRunId : RunManager.shared.currentRunId {
                JourneyPersistence.shared.aggregateStepsForRun(level: level, runId: runId) { map in
                    self.perMissionSteps = map
                }
            }
        }
        // Recompute points/steps when mission views report progress saved
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("missionProgressUpdated"))) { _ in
            let level = LevelStore.shared.currentLevel
            if let runId = isReadOnly ? replayRunId : RunManager.shared.currentRunId {
                JourneyPersistence.shared.aggregateStepsForRun(level: level, runId: runId) { map in
                    self.perMissionSteps = map
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { showQuitAlert = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
        }
        .background(DisableBackSwipe().frame(width: 0, height: 0))
        .alert("Quit adventure?", isPresented: $showQuitAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Quit", role: .destructive) {
                let level = LevelStore.shared.currentLevel
                RunManager.shared.cancelCurrentRun(level: level) { _ in
                    AnalyticsManager.shared.logEvent("adventure_quit", parameters: ["level": level])
                    dismiss()
                }
            }
        } message: {
            Text("If you go back now, your current adventure's progress will not be saved.")
        }
    }

    // MARK: - Sub-views
    private var header: some View {
        ZStack {
            Text("Guide")
                .font(.pressStart(24))
                .foregroundColor(.white)
                .offset(y: -14)
        }
    }

    private var pathStars: some View {
        let positions: [CGSize] = [
            CGSize(width: 20, height: -80),   // node 0 higher & right
            CGSize(width: -40, height: 10),   // node 1 unchanged
            CGSize(width: 50, height: 90),    // node 2 unchanged
            CGSize(width: -40, height: 180),  // node 3 raised
            CGSize(width: 30, height: 310)    // node 4 unchanged
        ]
        return GeometryReader { geo in
            ZStack {
                // Dotted connector behind nodes
                DottedConnector(points: connectorPoints(in: geo.size, offsets: positions))
                    .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 8]))
                    .foregroundColor(Color.gray.opacity(0.6))

                ForEach(themes.indices, id: \.self) { idx in
                    VStack(spacing: 4) {
                        if idx == 0 { Text("Start").font(.vt323(16)).foregroundColor(.white) }
                        let nodeState: MapNodeView.NodeStatus = idx < completed ? .done : (idx == completed ? .active : .pending)
                            MapNodeView(size: 70, status: nodeState)
                                .onTapGesture {
                                    guard idx <= completed else { return }
                                    selectedIdx = idx
                                    showGame = true
                                }
                        if idx == themes.count - 1 { Text("End").font(.vt323(16)).foregroundColor(.white) }
                    }
                    .offset(positions[idx])
                }
            }
        }
        .frame(height: 400)
        .offset(y: -100)
        .sheet(isPresented: $showGame) {
            let theme = themes[selectedIdx]
            let venue = theme.venueName
            let rawPunishment = theme.missions.gamesToPlay.first(where: { $0.localizedCaseInsensitiveContains("Loser") }) ?? "Loser buys the winner a snack."
            let punishment: String = {
                if let range = rawPunishment.range(of: "Loser") {
                    return String(rawPunishment[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
                } else {
                    return rawPunishment
                }
            }()
            let template = gameIntroTemplates[min(selectedIdx, gameIntroTemplates.count-1)]
            let description = String(format: template, venue, punishment)
            let imageName = imageForPunishment(punishment)
            MissionFlowView(
                missionIndex: selectedIdx,
                isReplay: selectedIdx < completed,
                gameDescription: description,
                taskText: theme.missions.task(for: 0),
                checkpointPrompt: theme.missions.checkpointPhoto,
                imageName: imageName,
                onFinish: {
                    completed += 1
                })
        }
    }

    private var generateReelButton: some View {
        Button("Generate Highlight Reel", action: generateReel)
            .font(.vt323(20))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.nodeTop)
            .foregroundColor(.white)
            .cornerRadius(8)
            .opacity(isAllCompleted ? 1 : 0.4)
            .disabled(!isAllCompleted)
            .padding(.top, 32)
            .padding(.bottom, 12)
    }

    // MARK: - Helpers
    private func imageForPunishment(_ text: String) -> String? {
        let map: [String:String] = [
            "carries winner": "punish_carry_stuff",
            "british accent": "punish_british_accent",
            "random under": "punish_buy_random",
            "tiktok": "punish_tiktok_dance",
            "sings one bar": "punish_sing_song",
            "slow-mo": "punish_slowmo_walk",
            "gum": "punish_ask_gum",
            "rhyme": "punish_speak_rhyme",
            "rizz": "punish_explain_rizz",
            "uber": "punish_call_uber",
            "third person": "punish_third_person",
            "yelp": "punish_yelp_compliment",
            "bestie vibes": "punish_bestie_vibes",
            "walks backwards": "punish_walk_backwards",
            "prank calls": "punish_call_mom",
            "ted talk": "punish_ted_frogs",
            "paparazzi": "punish_paparazzi"
        ]
        for (key, img) in map {
            if text.localizedCaseInsensitiveContains(key) { return img }
        }
        return nil
    }
    // Removed timeString; countdown timer no longer displayed

    private var isAllCompleted: Bool {
        guard let runId = RunManager.shared.currentRunId else { return false }
        var result = false
        let semaphore = DispatchSemaphore(value: 0)
        JourneyPersistence.shared.aggregateCompletionForRun(level: LevelStore.shared.currentLevel, runId: runId, missionCount: themes.count) { set in
            result = (set.count >= themes.count)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
        return result
    }

    private func generateReel() {
        guard let runId = RunManager.shared.currentRunId else { return }
        let level = LevelStore.shared.currentLevel
        HighlightReelBuilder.shared.buildReel(level: level, runId: runId) { res in
            if case .success(let url) = res {
                let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                UIApplication.shared.topMostViewController()?.present(av, animated: true)
            }
        }
    }

    // points removed in quest mode

    private func presentConfetti() {
        // Overlay a transient confetti view using a hosting window
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        guard let w = window, let root = w.rootViewController else { return }
        let host = UIHostingController(rootView: ConfettiView())
        host.view.backgroundColor = .clear
        host.view.frame = root.view.bounds
        root.view.addSubview(host.view)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            host.view.removeFromSuperview()
        }
    }
}

// MARK: - Dotted connector helper
fileprivate struct DottedConnector: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard points.count > 1 else { return p }
        p.move(to: points[0])
        for pt in points.dropFirst() { p.addLine(to: pt) }
        return p
    }
}

fileprivate func connectorPoints(in size: CGSize, offsets: [CGSize]) -> [CGPoint] {
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    return offsets.map { CGPoint(x: center.x + $0.width, y: center.y + $0.height) }
}

// MARK: - Reusable stacked circle node
struct StackedNodeView: View {
    let size: CGFloat
    let completed: Bool
    let blink: Bool
    @State private var pulse = false
    

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.nodeBottom)
                .frame(width: size, height: size)
                .offset(x: size * 0.08, y: size * 0.12)

            Circle()
                .fill(Color.nodeTop)
                .frame(width: size, height: size)

            // white outline
            Image(systemName: completed ? "star.fill" : "star")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.6)
                .foregroundColor(.white)
            // blinking golden overlay
            if blink && !completed {
                Image(systemName: "star.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.6)
                    .foregroundColor(.yellow)
                    .opacity(pulse ? 0.2 : 1)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            pulse.toggle()
                        }
                    }
            }
        }
        .frame(width: size * 1.3, height: size * 1.3, alignment: .top)
    }
}

#if DEBUG
struct AdventureMapView_Previews: PreviewProvider {
    static var previews: some View {
        AdventureMapView(themes: Array(repeating: CampusTheme.sample, count: 5), level: 1)
    }
}
#endif
