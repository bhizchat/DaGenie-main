import SwiftUI

struct ScenePlannerView: View, Identifiable {
    let id = UUID()
    let mainCharacter: CharacterItem

    // Allow clearing/replacing the primary character within this screen
    @State private var primaryCharacter: CharacterItem? = nil
    @State private var sideCharacter: CharacterItem? = nil
    @State private var plot: String = ""
    @State private var action: String = ""
    @State private var setting: String = ""
    @State private var showingPicker: Bool = false
    @State private var pickingForPrimary: Bool = false
    @State private var showingSettingsPicker: Bool = false
    @State private var selectedSetting: SceneSettingItem? = nil
    @State private var isPlanning: Bool = false

    init(mainCharacter: CharacterItem) {
        self.mainCharacter = mainCharacter
        _primaryCharacter = State(initialValue: mainCharacter)
    }

    private var isFormComplete: Bool {
        let hasPlot = !plot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAction = !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSetting = selectedSetting != nil
        return primaryCharacter != nil && sideCharacter != nil && hasPlot && hasAction && hasSetting
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    Text("SCENE PLANNER")
                        .font(.system(size: 18, weight: .bold))
                    HStack { Spacer(); CloseButton() }
                }
                .padding(.top, 12)

                // Character 1
                VStack(spacing: 8) {
                    Text("Character 1").font(.system(size: 14, weight: .semibold))
                    ZStack(alignment: .topTrailing) {
                        if let pc = primaryCharacter {
                            Image(pc.asset)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            // Remove button
                            Button(action: { primaryCharacter = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.black)
                                    .background(Color.white.opacity(0.9).clipShape(Circle()))
                            }
                            .padding(6)
                            .contentShape(Rectangle())
                        } else {
                            Button(action: { openCharacterPicker(forPrimary: true) }) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.2))
                                        .frame(height: 160)
                                    Image(systemName: "plus")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundColor(.black.opacity(0.7))
                                }
                            }
                        }
                    }
                }

                // Character 2 placeholder / selection
                VStack(spacing: 8) {
                    Text("Character 2").font(.system(size: 14, weight: .semibold))
                    if let sc = sideCharacter {
                        ZStack(alignment: .topTrailing) {
                            Image(sc.asset)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            Button(action: { sideCharacter = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.black)
                                    .background(Color.white.opacity(0.9).clipShape(Circle()))
                            }
                            .padding(6)
                            .contentShape(Rectangle())
                        }
                    } else {
                        Button(action: { openCharacterPicker(forPrimary: false) }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 160)
                                Image(systemName: "plus")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.black.opacity(0.7))
                            }
                        }
                    }
                }

                // Inputs
                VStack(alignment: .leading, spacing: 12) {
                    Text("Plot / Dialogue").font(.system(size: 14, weight: .semibold))
                    TextField("Add plot or dialogue", text: $plot, axis: .vertical)
                        .padding(10)
                        .foregroundColor(.black)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                    Text("Action").font(.system(size: 14, weight: .semibold))
                    TextField("Describe action", text: $action, axis: .vertical)
                        .padding(10)
                        .foregroundColor(.black)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                    Text("Setting").font(.system(size: 14, weight: .semibold))
                    Button(action: { showingSettingsPicker = true }) {
                        HStack {
                            Text(selectedSetting?.name ?? "Select a setting")
                                .foregroundColor(.black)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.black.opacity(0.6))
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                    }
                }
                .padding(.horizontal, 20)

                Button(action: { Task { await nextFromPlanner() } }) {
                    Text("NEXT")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 10).fill(isFormComplete ? Color.black : Color(hex: 0x999CA0)))
                        .padding(.horizontal, 20)
                }
                .disabled(!isFormComplete)
                .padding(.bottom, 20)
            }
        }
        .hideKeyboardOnTap()
        .background(Color(hex: 0xF7B451).ignoresSafeArea())
        .overlay {
            if isPlanning { ZStack { Color.black.opacity(0.25).ignoresSafeArea(); ProgressView("Planning…").padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Color.white)) } }
        }
        // Present a picker by overlaying a transparent StoriesView when needed
        .fullScreenCover(isPresented: $showingPicker) {
            StoriesView(onBack: { showingPicker = false }, onPickCharacter: { picked in
                if pickingForPrimary {
                    primaryCharacter = picked
                } else {
                    sideCharacter = picked
                }
                showingPicker = false
            })
        }
        .fullScreenCover(isPresented: $showingSettingsPicker) {
            SceneSettingsPickerView(onBack: { showingSettingsPicker = false }, onPick: { item in
                selectedSetting = item
                setting = item.key
                showingSettingsPicker = false
            })
        }
    }

    private func openCharacterPicker(forPrimary: Bool) {
        pickingForPrimary = forPrimary
        showingPicker = true
    }

    private func nextFromPlanner() async {
        guard isFormComplete else { return }
        isPlanning = true
        defer { isPlanning = false }
        let primaryId = primaryCharacter?.asset ?? mainCharacter.asset
        let secondaryId = sideCharacter?.asset
        let settingKey = selectedSetting?.key
        let refs = PlannerService.defaultRefs(primaryId: primaryId, secondaryId: secondaryId, settingKey: settingKey)
        let req = PlannerService.ScenePlannerRequest(
            primaryCharacterId: primaryId,
            secondaryCharacterId: secondaryId,
            plot: plot,
            action: action,
            settingKey: settingKey ?? "",
            referenceImageUrls: refs,
            sceneCount: 6,
            requestId: UUID().uuidString,
            schemaVersion: 1,
            locale: Locale.current.identifier,
            aspectRatio: "16:9"
        )
        do {
            let plan = try await PlannerService.shared.planFromScene(req)
            if let vc = UIApplication.shared.topMostViewController() {
                let host = UIHostingController(rootView: StoryboardNavigatorView(plan: plan))
                vc.present(host, animated: true)
            }
        } catch {
            print("[ScenePlanner] planFromScene failed: \(error)")
        }
    }
}

private struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}



