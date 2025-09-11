//  CreateAdventureView.swift
//  Matches screenshot #1 – form to generate themes.
//
import SwiftUI

struct CreateAdventureView: View {
    @StateObject private var vm = CreateAdventureVM()
    @State private var showMenu = false
    @State private var showSaved = false
    @StateObject private var savedPlansVM = SavedPlansVM()
    @EnvironmentObject private var huntsRepo: HuntsRepository
    @EnvironmentObject private var userRepo: UserRepository
    @State private var showThemes = false
    @State private var showSwipeOnboarding = false
    @FocusState private var collegeFocused: Bool
    @State private var showErrorAlert = false

    var body: some View {
        NavigationStack {
        ZStack {
            
            ScrollView {
                
                VStack(alignment: .leading, spacing: 20) {
                    Text("Create your Adventure")
                        .font(.pressStart(18))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.bottom, 12)
                    collegeField
                    moodChips
                    VStack(alignment: .leading, spacing: 4) {
                        Text("EXTRA DETAIL…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("(Optional)", text: $vm.extraDetail)
                            .textFieldStyle(.roundedBorder)
                    }
                    timePicker

                    Button(action: {
                        Task {
                            await vm.generateThemes()
                            if !vm.themes.isEmpty { showThemes = true }
                        }
                    }) {
                        Text("Generate Options")
                            .font(.custom("Courier", size: 26).bold())
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isLoading || vm.collegeLat == 0 || vm.collegeLng == 0)
                    .padding(.top, 30)
                    
                    // Error display
                    if let error = vm.error {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.top, 8)
                    }
                }
                .padding()
            }
            .hideKeyboardOnTap()
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
                .environmentObject(AuthViewModel())
                .frame(width: 260, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.move(edge: .leading))
                .zIndex(3)
            }

            NavigationLink(destination: ThemeSwipeView(themes: vm.themes)
                .environmentObject(savedPlansVM), isActive: $showThemes) { EmptyView() }.hidden()
            NavigationLink(destination: SavedDatesView().environmentObject(savedPlansVM), isActive: $showSaved) { EmptyView() }.hidden()
            // Onboarding removed per new flow

            if vm.isLoading {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle(tint: Color(red: 242/255, green: 109/255, blue: 100/255)))
                        .frame(width: 200)
                    Text("Loading…")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                }
            }

        
        }
        .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { withAnimation { showMenu.toggle() } }) {
                        Image(systemName: "line.3.horizontal")
                            .imageScale(.large)
                    }
                }
            }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("stats_go_home"))) { _ in
            // Ensure the side menu opens so users see updated points and can tap Journey
            withAnimation { showMenu = true }
        }
        }
    }

    private var collegeField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COLLEGE")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("College", text: $vm.college)
                .submitLabel(.done)
                .textFieldStyle(.roundedBorder)
                .focused($collegeFocused)
            if !vm.collegeSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(vm.collegeSuggestions, id: \.self) { suggestion in
                        Button(action: {
                            vm.selectCollege(suggestion)
                            collegeFocused = false
                        }) {
                            Text(suggestion.name)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(Color(.secondarySystemBackground))
                .cornerRadius(6)
            }
        }
    }

    // Generic helper remains, but consider overriding when placeholder differs
    private func textField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var moodChips: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MOOD / VIBE (Choose 1 or more)")
                .font(.caption)
                .foregroundColor(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                let moodOptions: [(String,String)] = [
                        ("Artsy","paintbrush"),
                        ("Outdoorsy","leaf"),
                        ("Boba Stop","cup.and.saucer"),
                        ("Comfort Bites","fork.knife"),
                        ("Bar Hop","wineglass"),
                        ("Romantic","heart"),
                        ("Arcade","gamecontroller"),
                        ("Live Music","music.mic")]
                     ForEach(moodOptions, id: \.0) { option in
                         Chip(label: option.0, icon: option.1, isSelected: vm.moods.contains(option.0)) {
                             if vm.moods.contains(option.0) {
                             vm.moods.remove(option.0)
                         } else {
                             vm.moods.insert(option.0)
                         }
                         }
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 4) {
            ProgressView()
                .progressViewStyle(LinearProgressViewStyle(tint: .red))
                .frame(height: 8)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .cornerRadius(4)
            Text("Loading...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var timePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TIME OF DAY")
                .font(.caption)
                .foregroundColor(.secondary)
            DropdownPicker(selection: $vm.timeOfDay, options: ["Any","Morning","Afternoon","Evening"], placeholder: "Time")
        }
    }
}

#if DEBUG
struct CreateAdventureView_Previews: PreviewProvider {
    static var previews: some View {
        CreateAdventureView()
            .environmentObject(HuntsRepository.shared)
            .environmentObject(UserRepository.shared)
            
            
    }
}
#endif
