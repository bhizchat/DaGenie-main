//
//  GenerateView.swift
//  DateGenie
//
//  Created by AI on 7/17/25.
//  A simple SwiftUI form to collect user inputs and display generated date plans.
//

import SwiftUI
import EventKit
import EventKitUI
import FirebaseAuth
import FirebaseFirestore
import AVFoundation

private let kFunctionsBaseURL = "https://us-central1-dategenie-dev.cloudfunctions.net"

// MARK: - Model
struct Venue: Codable {
    let name: String
    let address: String?
    let rating: Double?
    let photoUrl: String?
    let mapsUrl: String?
}

struct Scores: Codable {
    let romance: Double
    let vibes: Double
    let food: Double
    let hype: Double
}

struct DatePlan: Identifiable, Codable {
    let id: String
    let title: String
    let itinerary: String
    let heroImgUrl: String?
    let venue: Venue?
    let scores: Scores?
    // Optional distance in meters so we can show "X miles away" after saving
    let distanceMeters: Int?
}

// MARK: - View
struct GenerateView: View {
    @State private var showMenu = false
    @State private var showSaved = false
    @StateObject private var savedPlansVM = SavedPlansVM()
    @EnvironmentObject var auth: AuthViewModel
    // Inputs
    @State private var location: String = ""
    @StateObject private var locVM = LocationSearchVM()
    @FocusState private var isLocationFocused: Bool
    @State private var preferences: String = ""
    @State private var budgetIndex: Int = 0
    @State private var timeIndex: Int = 0

    // Result
    @State private var plans: [DatePlan] = []
    @AppStorage("seenSwipeHint") private var seenSwipeHint: Bool = false
    @State private var tabIndex: Int = 0
    @State private var showDeleteConfirm = false
    @State private var swipeAnim = false
    @State private var isLoading: Bool = false
    @State private var progress: Double = 0
    @State private var errorMsg: String?
    @State private var showDone = false
    @State private var showPaywall = false
    @AppStorage("requestedPushAuth") private var requestedPushAuth: Bool = false

    private let budgets = ["$", "$$", "$$$"]
    private let times = ["any", "morning", "afternoon", "evening"]
    
    private var canGenerate: Bool {
        !location.isEmpty && (!selectedVibes.isEmpty || !preferences.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    private let vibes = ["Artsy", "Outdoorsy", "Cozy", "Foodie", "Bar Hop", "Romantic"]
    @State private var selectedVibes: Set<String> = []
    
    // Stable wrapper for search completions
    private struct CompletionRow: Identifiable, Hashable {
        let title: String
        let subtitle: String
        var id: String { title + subtitle } // stable across refreshes
    }

    private func accept(_ row: CompletionRow) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let full = row.title + (row.subtitle.isEmpty ? "" : ", \(row.subtitle)")
        location = full
        locVM.query = full
        UIApplication.hideKeyboard()
        DispatchQueue.main.async {
            locVM.suggestions.removeAll()
            isLocationFocused = false
        }
    }
    
    private func toggleVibe(_ vibe: String) {
        let isSelected = selectedVibes.contains(vibe)
        if isSelected { selectedVibes.remove(vibe) } else { selectedVibes.insert(vibe) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    var body: some View {
        ZStack {
            if showMenu {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { showMenu = false } }
                    .zIndex(2)
                SideMenuView(onClose: { withAnimation { showMenu = false } }, onSelectSaved: {
                    showSaved = true
                })
                .environmentObject(UserProfile())
                .environmentObject(savedPlansVM)
                .environmentObject(auth)
                .frame(width: 260, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.move(edge: .leading))
                .zIndex(3)
            }
            NavigationStack {
                
                Group {
                    if plans.isEmpty {
                        formView
                    } else {
                        plansTabView
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarHidden(false)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { withAnimation { showMenu.toggle() } }) {
                            Image(systemName: "line.3.horizontal")
                                .imageScale(.large)
                                .foregroundColor(.accentPrimary)
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        Text("Plan a Date ")
                            .font(.custom("Sacramento-Regular", size: 32))
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if !plans.isEmpty {
                            Button("New") { reset() }
                        }
                    }
                }
                .confirmationDialog("Delete your account? This cannot be undone.", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete Account", role: .destructive) {
                        Task { await auth.deleteAccount() }
                    }
                    Button("Cancel", role: .cancel) { }
                }
                .alert("Error", isPresented: Binding(get: { errorMsg != nil }, set: { _ in errorMsg = nil })) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(errorMsg ?? "Unknown error")
                }
            }
            .sheet(isPresented: $showSaved) { SavedDatesView().environmentObject(savedPlansVM) }
                .sheet(isPresented: $showPaywall) { PaywallView() }
            .onAppear { UIScrollView.appearance().delaysContentTouches = false }
                .onReceive(NotificationCenter.default.publisher(for: .pointsAwarded)) { _ in
                    SoundPlayer.shared.playSuccess()
                    withAnimation { showMenu = true }
                    DispatchQueue.main.asyncAfter(deadline: .now()+1.5) {
                        withAnimation { showMenu = false }
                    }
                }
            if isLoading {
                LoadingBarOverlay(progress: $progress)
            } else if showDone {
                DoneOverlay().transition(.opacity)
            }
        }
    }

    // MARK: - Subviews
    private var formView: some View {
        Form {
            
            Section(header: Text("Location")) {
                TextField("Start typing a place…", text: $location)
                    .onChange(of: location) { newValue in
                        locVM.query = newValue
                    }
                    .focused($isLocationFocused)
                    .textInputAutocapitalization(.words)

                let suggestionRows = locVM.suggestions.map { CompletionRow(title: $0.title, subtitle: $0.subtitle) }
                if !suggestionRows.isEmpty {
                    ForEach(suggestionRows.indices, id: \.self) { index in
                        Button(action: {}) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestionRows[index].title).bold()
                                    if !suggestionRows[index].subtitle.isEmpty {
                                        Text(suggestionRows[index].subtitle)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: true, vertical: false)
                        .highPriorityGesture(TapGesture().onEnded { accept(suggestionRows[index]) })
                    }
                }
            }
            Section(header: Text("Mood / Vibe")) {
                // Chips grid
                LazyVGrid(columns: Array(repeating: GridItem(.adaptive(minimum: 80), spacing: 8), count: 3), spacing: 8) {
                    ForEach(vibes, id: \.self) { vibe in
                        let isSelected = selectedVibes.contains(vibe)
                        Button(action: { toggleVibe(vibe) }) {
                            HStack {
                                Spacer(minLength: 0)
                                Text(vibe)
                                    .font(.caption)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .foregroundColor(isSelected ? .white : .accentPrimary)
                                Spacer(minLength: 0)
                            }
                            .frame(minWidth: 80)
                            .background(isSelected ? Color.accentPrimary : Color.clear)
                            .overlay(
                                Capsule()
                                    .stroke(Color.accentPrimary, lineWidth: 1)
                            )
                            .cornerRadius(16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)

                TextField("Optional extra detail…", text: $preferences)
            }
            Section(header: Text("Budget")) {
                Picker("Budget", selection: $budgetIndex) {
                    ForEach(0..<budgets.count, id: \..self) { i in
                        Text(budgets[i]).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                 .tint(.accentPrimary)
            }
            Section(header: Text("Time of Day")) {
                Picker("Time", selection: $timeIndex) {
                    ForEach(0..<times.count, id: \..self) { i in
                        Text(times[i].capitalized).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                 .tint(.accentPrimary)

Section {
HStack {
Spacer(minLength: 0)
Button(action: fetchPlans) {
Text("Generate Plans")
                            .font(.title2).bold()
.frame(maxWidth: .infinity)
.padding(.vertical, 18)
}
.buttonStyle(.borderedProminent)
.controlSize(.regular)
.tint(.accentPrimary)
.disabled(!canGenerate || isLoading || SubscriptionManager.shared.backendSyncInProgress)
.contentShape(Rectangle())
Spacer(minLength: 0)
}
.padding(.top, 16)
                    .listRowBackground(Color.clear)
}
}
.scrollDismissesKeyboard(.interactively)
.onTapGesture { UIApplication.hideKeyboard() }
}
        .scrollDismissesKeyboard(.interactively)
        
        .simultaneousGesture(TapGesture().onEnded { UIApplication.hideKeyboard() })
    }

    private var plansTabView: some View {
        ZStack {
            TabView(selection: $tabIndex) {
                ForEach(Array(plans.enumerated()), id: \ .element.id) { idx, plan in
                    PlanCardView(plan: plan)
                        .environmentObject(savedPlansVM)
                        .tag(idx)
                        .padding()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .onChange(of: tabIndex) { _ in seenSwipeHint = true }
            // Hide hint after 5s if still visible
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now()+5) { seenSwipeHint = true }
            }
            if !seenSwipeHint {
                SwipeHintView(animate: $swipeAnim)
                    .onAppear { swipeAnim = true }
            }
        }
    }

    // MARK: - Networking
    private func fetchPlans() {
        func performRequest(token: String?) {
            let url = URL(string: "\(kFunctionsBaseURL)/generatePlans")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 300
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            if let tk = token {
                request.addValue("Bearer \(tk)", forHTTPHeaderField: "Authorization")
            }
            let body: [String: Any] = [
                "location": location,
                "preferences": (Array(selectedVibes).joined(separator: ", ") + (preferences.isEmpty ? "" : ", " + preferences)).trimmingCharacters(in: .whitespacesAndNewlines),
                "budget": budgets[budgetIndex],
                "timeOfDay": times[timeIndex]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    isLoading = false
                    withAnimation { showDone = true }
                    DispatchQueue.main.asyncAfter(deadline: .now()+1.2) { showDone = false }
                }
                if let error = error {
                    DispatchQueue.main.async { self.errorMsg = error.localizedDescription }
                    return
                }
                guard let httpResp = response as? HTTPURLResponse else { return }
                if httpResp.statusCode == 402 {
                    if SubscriptionManager.shared.isSubscribed {
                        // Backend may not have processed the latest receipt yet – inform user instead of erroring.
                        DispatchQueue.main.async { self.errorMsg = "Your subscription is processing. Please try again in a few seconds." }
                    } else {
                        DispatchQueue.main.async { self.showPaywall = true }
                    }
                    return
                }
                if httpResp.statusCode != 200 {
                    let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    DispatchQueue.main.async { self.errorMsg = "Server \(httpResp.statusCode): \(bodyText.prefix(120))" }
                    return
                }
                guard let data = data else { return }
                do {
                    let decoded = try JSONDecoder().decode(ResponseWrapper.self, from: data)
                    DispatchQueue.main.async {
                        self.plans = decoded.plans
                        if !requestedPushAuth {
                            requestedPushAuth = true
                            PushNotificationManager.shared.requestAuthorization()
                        }
                    }
                } catch {
                    let txt = String(data: data, encoding: .utf8) ?? ""
                    DispatchQueue.main.async { self.errorMsg = "Parse error: \(txt.prefix(120))" }
                }
            }.resume()
        }

        guard !isLoading else { return }
        isLoading = true
        progress = 0
        withAnimation(.linear(duration: 4)) { progress = 1 }
        showDone = false
        errorMsg = nil

        // Retrieve Firebase ID token if signed in
        if let user = Auth.auth().currentUser {
            user.getIDTokenForcingRefresh(false) { token, error in
                performRequest(token: token)
            }
        } else {
            performRequest(token: nil)
        }
        return // request sent above
    }

    private func reset() {
        plans = []
    }

    // Wrapper to match backend
    private struct ResponseWrapper: Decodable {
        let plans: [DatePlan]
    }
}

// MARK: - EventKitUI wrapper
private struct EventEditView: UIViewControllerRepresentable {
    let plan: DatePlan
    let defaultDates: (Date, Date)
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = plan.title
        event.location = plan.venue?.address
        event.notes = plan.itinerary
        event.url = URL(string: plan.venue?.mapsUrl ?? "")
        event.startDate = defaultDates.0
        event.endDate = defaultDates.1
        let vc = EKEventEditViewController()
        vc.eventStore = store
        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }
    
    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}
    
    class Coordinator: NSObject, EKEventEditViewDelegate {
        let parent: EventEditView
        init(_ parent: EventEditView) { self.parent = parent }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            controller.dismiss(animated: true)
        }
    }
}

// Simple tile for score display
private struct ScoreTile: View {
    let emoji: String
    let title: String
    let value: Double
    @State private var showInfo = false
    var body: some View {
        HStack(spacing: 6) {
            Text(emoji)
                .font(.title3)
            Text("\(title) : \(Int(value.rounded()))/10")
                .font(.system(size: 17, weight: .bold, design: .rounded))
        }
        .padding(8)
        .fixedSize(horizontal: true, vertical: false)
        .background(Color.white)
        .cornerRadius(6)
        .foregroundColor(.black)
        .onTapGesture { showInfo = true }
        .popover(isPresented: $showInfo) {
            Text(infoText)
                .padding()
                .font(.body)
        }
        .accessibilityLabel("\(title) score \(Int(value.rounded())) out of 10")
    }
    private var infoText: String {
        switch title {
        case "Romance": return "Measures how romantic or intimate the venue and plan feel."
        
        case "Food": return "Represents food quality based on ratings."
        
        default: return ""
        }
    }
}

// Simple subtle swipe hint overlay
private struct SwipeHintView: View {
    @Binding var animate: Bool
    var body: some View {
        HStack(spacing: 4) {
            Text("Swipe")
                .font(.footnote)
                .foregroundColor(.secondary)
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .offset(x: animate ? 6 : 0)
                .opacity(animate ? 0 : 1)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: animate)
        }
        .padding(8)
        .background(.thinMaterial)
        .cornerRadius(8)
        .padding(.bottom, 50)
        .transition(.opacity)
        .accessibilityHidden(true)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

// MARK: - Plan Card
struct PlanCardView: View {
    let plan: DatePlan
    @EnvironmentObject var savedVM: SavedPlansVM
    @State private var showEventSheet = false
    @State private var showCamera = false
    @State private var showTutorial = false
    @AppStorage("hasSeenPointsTutorial") private var hasSeenPointsTutorial: Bool = false
    // animated score values
    @State private var animRomance: Double = 0
    
    private func eventDefaultDates() -> (Date, Date) {
        // default tomorrow 7-9 PM local
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 19, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: Date())!)!
        let end = cal.date(byAdding: .hour, value: 2, to: start)!
        return (start, end)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let urlString = plan.heroImgUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty: ProgressView()
                        case .success(let img): img.resizable().scaledToFill()
                        case .failure: Image(systemName: "photo")
                        @unknown default: EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .clipped()
                    .cornerRadius(12)
                }

                Text(plan.title)
                    .font(.title3).bold()
                Text(plan.itinerary)
                    .font(.body)
                if let maps = plan.venue?.mapsUrl, let url = URL(string: maps) {
                    Link("Venue: \(plan.venue?.name ?? "Venue")", destination: url)
                        .font(.subheadline)
                } else {
                    Text("Venue: \(plan.venue?.name ?? "Unknown venue")")
                        .font(.subheadline)
                }
                if let addr = plan.venue?.address {
                    HStack {
                        Text(addr)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 0)
                        Button(action: { UIPasteboard.general.string = addr }) {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Copy address")
                    }
                }
                HStack(spacing: 12) {
                    ScoreTile(emoji: "❤️", title: "Romance", value: animRomance)
                    Button(action: { savedVM.toggleSave(plan: plan) }) {
                        Image(systemName: savedVM.savedIds.contains(plan.id) ? "bookmark.fill" : "bookmark")
                            .font(.title3)
                            .foregroundColor(.pink)
                    }
                    .accessibilityLabel(savedVM.savedIds.contains(plan.id) ? "Unsave" : "Save")
                }
                .onAppear {
                        withAnimation(.easeOut(duration: 0.6)) {
                            animRomance = plan.scores?.romance ?? 0
                        }
                    }
                .accessibilityElement(children: .contain)
                .font(.caption)
                .foregroundColor(.secondary)
                HStack {
                    Button("Add to Calendar") { showEventSheet = true }
                        .sheet(isPresented: $showEventSheet) { EventEditView(plan: plan, defaultDates: eventDefaultDates()) }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentPrimary)
                    Button("Get Romance Points") {
                        guard !UserDefaults.standard.bool(forKey: "awarded_\(plan.id)") else { return }

                        if hasSeenPointsTutorial {
                            showCamera = true
                        } else {
                            showTutorial = true
                        }
                    }
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                    .disabled(UserDefaults.standard.bool(forKey: "awarded_\(plan.id)"))
                }
                .padding(.top, 8)
                .sheet(isPresented: $showTutorial) {
                    PointsTutorialView {
                        hasSeenPointsTutorial = true
                        showTutorial = false
                        showCamera = true
                    }
                }
                .fullScreenCover(isPresented: $showCamera) {
                    PointsPhotoCaptureView(points: Int((plan.scores?.romance ?? 0).rounded()), planId: plan.id, planTitle: plan.title)
                }
            }
            .padding()
            
        }
    }
}

// ...
#Preview {
    GenerateView()
}
