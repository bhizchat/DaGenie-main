//
//  SideMenuView.swift
//  DateGenie
//
//  Simple slide-in sidebar showing romance points, navigation, and account actions.
//

import SwiftUI
import FirebaseAuth

struct SideMenuView: View {
    var onClose: () -> Void
    @EnvironmentObject var profile: UserProfile
    @EnvironmentObject var savedPlans: SavedPlansVM
    @EnvironmentObject var auth: AuthViewModel
        var onSelectSaved: () -> Void
    @State private var showLevels = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Saved Plans entry (replaces Team Score)
            Button(action: { onSelectSaved(); onClose() }) {
                HStack(spacing: 12) {
                    Image("icon_saved_dates")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    Text("Saved Plans")
                        .font(.headline)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            NavigationLink(destination: HighlightsView()) {
                Text(" 🎬 Highlights")
            }
            .buttonStyle(.plain)
            Divider()
            Button {
                try? Auth.auth().signOut()
                onClose()
            } label: {
                Label("Sign Out", systemImage: "arrow.backward.circle")
            }
            .buttonStyle(.plain)
            Button(role: .destructive) {
                Task {
                    await auth.deleteAccount()
                onClose()
                }
            } label: {
                Label("Delete Account", systemImage: "trash")
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 260, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showLevels) { RomanceLevelsView() }
    }
}
