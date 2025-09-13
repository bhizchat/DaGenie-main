//  HuntDiscoveryView.swift
//  DateGenie
//
import SwiftUI

struct HuntDiscoveryView: View {
    @EnvironmentObject private var huntsRepo: HuntsRepository
    @EnvironmentObject private var userRepo: UserRepository

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if huntsRepo.hunts.isEmpty {
                    ProgressView("Loading hunts…")
                        .task {
                            await refresh()
                        }
                } else {
                    TabView {
                        ForEach(filteredHunts) { hunt in
                            HuntCardView(hunt: hunt) {
                                startHunt(hunt)
                            }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                }
            }
            .navigationTitle("Choose a Hunt")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { Task { await refresh() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .errorToast(message: $errorMessage)
    }

    private var filteredHunts: [HuntTemplate] {
        huntsRepo.hunts.filter { hunt in
            hunt.budgetUSD <= userRepo.prefs.maxBudget &&
            (!userRepo.prefs.lowMobility || hunt.clues.allSatisfy { $0.mobility != "stairs_ok" })
        }
    }

    private func startHunt(_ hunt: HuntTemplate) {
        // TODO: create dates/{id} doc and navigate to LiveHuntView
    }

    private func refresh() async {
        do {
            try await huntsRepo.refresh()
        } catch {
            errorMessage = "Failed to refresh hunts."
        }
    }
}

#if DEBUG
struct HuntDiscoveryView_Previews: PreviewProvider {
    static var previews: some View {
        HuntDiscoveryView()
            .environmentObject(HuntsRepository.shared)
            .environmentObject(UserRepository.shared)
    }
}
#endif
